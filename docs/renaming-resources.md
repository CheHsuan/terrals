# Terraform 資源改名的正確做法：address 不等於實體

這份文件記錄一個在階段 2 開發過程中真實踩到的問題：把 `aws_s3_bucket.terrals-lambda-artifacts` 改名成 `aws_s3_bucket.terrals_lambda_artifacts`（純粹的命名風格統一，`bucket = "..."` 這個實際欄位完全沒變），`terraform plan` 卻回報：

```
Plan: 4 to add, 0 to change, 2 to destroy.
```

也就是說：**只是把程式碼裡的識別碼從 kebab-case 改成 snake_case，Terraform 打算把兩個已經在雲端真實存在的資源（S3 bucket 與它的 public access block）整個刪掉重建。** 這在 LocalStack 上頂多是重跑一次 apply，但同一個操作發生在 prod 的 S3 bucket 或 DynamoDB table 上，代表：bucket 裡的物件、DynamoDB 的資料、依賴這個資源 ARN 的其他資源／IAM policy，全部要重新處理一次，而且中間有一段時間該資源不存在。

## 為什麼會這樣：state 用 address 當 key，不是用雲端身份

Terraform state 檔案內部是用「resource address」（`<type>.<name>`，例如 `aws_s3_bucket.terrals-lambda-artifacts`）當作查表的 key，不是用這個資源在 AWS 上的真實身份（ARN、bucket name、table name）。

當你把 `.tf` 裡的 resource label 改掉，Terraform 看到的是：

- state 裡有一個叫 `aws_s3_bucket.terrals-lambda-artifacts` 的東西，但新的設定檔裡已經沒有這個 address 了 → 判定為「使用者要刪除它」。
- 設定檔裡有一個叫 `aws_s3_bucket.terrals_lambda_artifacts` 的新 resource block，state 裡從來沒看過這個 address → 判定為「使用者要新建一個」。

Terraform 不會自動去比對「這兩個 resource block 的 `bucket = "..."` 剛好是同一個字串，所以大概是同一個東西改了名字」——它沒有這種語意推論，purely address-based。這正是本專案這次踩到的情況：**兩邊的 `bucket` 引數是完全相同的字面值 `"terrals-lambda-artifacts"`，DynamoDB 的 `name = "User"` 也完全沒變，但因為 resource label 改了，plan 依然是整個 destroy + create。**

## 三種不同的「改名」，處理方式不一樣

先分清楚你要改的到底是哪一層，這是選對工具的前提：

### 1. 只改 Terraform 內部識別碼（resource label／address）
例如這次的 `terrals-lambda-artifacts` → `terrals_lambda_artifacts`，或是把某個 resource 搬進一個 module。雲端上實際的欄位（bucket name、table name、ARN）完全沒變。**這純粹是 state 記帳問題，可以做到零實際變更**——見下方「解法」。

### 2. 改到雲端資源的真實身份欄位
例如把 S3 bucket 名稱從 `terrals-lambda-artifacts` 改成 `terrals-prod-artifacts`，或改 DynamoDB 的 `name`。這類欄位在 AWS provider 裡通常標記為 *ForceNew*／*requires replacement*——因為 S3、DynamoDB 這些服務本身沒有「原地改名」的 API。**這種情況不管你怎麼操作 state，Terraform 都必須真的 destroy + create**，`moved` block 或 `state mv` 只能處理第 1 種問題，救不了這種；真正安全的做法是先建新資源、把資料/流量遷移過去、確認沒問題後再刪舊資源（藍綠遷移），而不是依賴 Terraform 的 replace 語意。

### 3. 從獨立 resource 搬進／搬出 module，或跨 state 搬遷
Address 變了（例如從 `aws_s3_bucket.foo` 變成 `module.storage.aws_s3_bucket.foo`），但底層資源通常沒變——性質上跟第 1 種一樣，工具也相同，只是換 module 路徑時要小心 state 是否也需要跨檔案搬（`terraform state mv` 支援 `-state-out`）。

本文件討論的重點是第 1 種，也是絕大多數重構、統一命名風格會遇到的情境。

## 解法一：`moved` block（推薦，Terraform ≥ 1.1）

寫在 `.tf` 裡、跟著程式碼一起進版控的宣告式寫法：

```hcl
moved {
  from = aws_s3_bucket.terrals-lambda-artifacts
  to   = aws_s3_bucket.terrals_lambda_artifacts
}

moved {
  from = aws_s3_bucket_public_access_block.terrals-lambda-artifacts
  to   = aws_s3_bucket_public_access_block.terrals_lambda_artifacts
}
```

**這是本文件唯一附上實測結果的方案**：把這兩個 block 加進 `envs/dev/main.tf` 之後，同一份 rename 重新跑一次 `terraform plan`，結果從

```
Plan: 4 to add, 0 to change, 2 to destroy.
```

變成

```
Plan: 2 to add, 1 to change, 0 to destroy.
```

（`2 to add` 是這次 stage 2 本來就要新增的 DynamoDB table／item，跟 rename 無關；S3 bucket 變成 `will be updated in-place`，只有 tags 的差異，bucket 本身完全沒被刪除重建。）

為什麼推薦這個方案：
- **跟著 commit 走**：其他人拉下你的分支、任何一台跑 `terraform plan` 的機器（CI、隊友的筆電）都會自動套用這個對應關係，不需要額外手動操作。
- **可以在 apply 前用 `terraform plan` 先確認**效果，出錯了改完 `moved` 內容重新 plan 就好，沒有「已經對 state 動手」這種不可逆的中間狀態。
- `moved` block 可以留在程式碼裡不用清掉；Terraform 官方文件也建議永久保留，避免有人拉到很舊的分支、跳過中間幾次 rename 時失去對應關係。

## 解法二：`terraform state mv`（指令式，適合一次性、單機處理）

```bash
terraform state mv \
  'aws_s3_bucket.terrals-lambda-artifacts' \
  'aws_s3_bucket.terrals_lambda_artifacts'

terraform state mv \
  'aws_s3_bucket_public_access_block.terrals-lambda-artifacts' \
  'aws_s3_bucket_public_access_block.terrals_lambda_artifacts'
```

效果跟 `moved` block 相同，但差異是：**這個操作只改了你手上這一份 state**，不會進版控、不會自動套用到其他人的環境或 CI runner。如果團隊裡任何人先跑了 `.tf` 已經改完名字的版本，但還沒跑過這行 `state mv`，一樣會踩到本文開頭的 `4 to add, 2 to destroy`。

適用時機：
- Terraform < 1.1，還沒有 `moved` block 可用。
- 一次性、只影響自己本機這份 state 的操作（例如清理實驗用的 workspace）。
- 需要跨 state 檔案搬遷（`-state-out` 指定不同的 state 檔），這是 `moved` block 做不到的。

## 解法三：什麼都不做，接受 destroy + create

如果這個資源本來就是可以重建、沒有下游相依、不是 prod 資料（例如這次 dev 環境裡的練習用資源），直接讓 Terraform 刪掉重建也是合理選擇——**這也是我們在這個 repo 目前的實際做法**：階段 2 這次 rename 就是刻意接受 destroy/create，把重點留給 tfvars 參數化本身，沒有另外補 `moved` block。差別在於「知道自己在接受什麼」而不是被 plan 嚇一跳才發現。

適合接受 destroy/create 的判斷條件：
- 資源本身無狀態，或狀態可以重新產生（例如這次的空 bucket）。
- 沒有其他資源、應用程式、DNS 記錄硬編碼了這個資源的 ARN／ID。
- 不是被 `prevent_destroy` 保護的資源（階段 5 的 prod DynamoDB table 就屬於「絕對不能接受這個答案」的那一類——這正是 `prevent_destroy` 存在的理由：擋下這種因為 rename 誤觸的 destroy）。

## 對照表

| 方案 | 進版控 | 適用 Terraform 版本 | 能跨 state 搬 | 需要的操作 |
|---|---|---|---|---|
| `moved` block | ✅ | ≥ 1.1 | ❌ | 寫 `.tf`，`plan` 驗證 |
| `terraform state mv` | ❌（只影響本機/當下 state） | 任何版本 | ✅（`-state-out`） | 跑一次 CLI 指令 |
| 接受 destroy/create | — | 任何版本 | — | 什麼都不做，但要先確認代價可接受 |

## 上 prod 前的檢查清單

把這個問題往前延伸到階段 5（多環境與生命週期管理）：

- [ ] Rename 任何 resource label 之前，先跑一次 `terraform plan`，確認 summary 是不是出現非預期的 `to destroy`。
- [ ] 如果是第 1 類問題（只改 address），一律用 `moved` block，不要用 `state mv` 然後忘記告訴隊友。
- [ ] 如果是第 2 類問題（改到真實身份欄位、provider 判定為 ForceNew），評估是否需要藍綠遷移，而不是直接讓它 replace。
- [ ] Prod 的關鍵有狀態資源（DynamoDB table、RDS）應該掛 `lifecycle { prevent_destroy = true }`，這樣就算漏看了 plan 裡的 `to destroy`，apply 也會在動手前被擋下來。
