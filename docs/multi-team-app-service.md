# 從 Step 2 到 Step 3：多團隊共用 app_service 的設計決策

Step 2 的 `envs/dev/` 只服務一份部署：資源命名、參數都寫死，沒有「這是哪個團隊的」這個維度。Step 3 要把 Lambda + API Gateway + DynamoDB + IAM 變成一套多個團隊能共用的標準模組，這個轉換過程會遇到四個問題，這份文件依序記錄每個問題的決策。

## 1. 多團隊有不同的參數，該怎麼設計比較好

一旦不只一個團隊要用同一套資源定義，每個團隊需要的識別資訊（叫什麼名字）就不能再寫死。有兩種設計方向：

**選項 A**：每個資源的名稱各自是一個獨立變數，團隊呼叫模組時要把 `lambda_artifacts_name`、`dynamodb_user_table_name`、`lambda_function_name`… 全部手動填上團隊前綴。
缺點：變數一多，團隊很容易漏改其中一個而撞名；命名規則（前綴放哪裡、用 `-` 還是 `_`）會散落在各團隊自己的呼叫端，無法保證一致。

**選項 B（採用）**：模組新增一個必填的 `var.owner`，內部用 `locals` 統一組出一個前綴（`name_prefix = "${var.owner}-${local.project}"`），所有資源名稱都從這個 local 衍生，不再讓呼叫端各自替每個資源命名。

**決策：採用選項 B。** 理由：命名規則是平台該負責保證一致的事，不該讓每個消費模組的團隊各自發明。團隊呼叫模組時只需要回答「我是誰」（`owner`），不用管「每個資源該叫什麼」。

## 2. 為什麼需要 module

Step 2 的做法是把所有資源直接寫在 `envs/dev/main.tf` 裡，只描述「一份部署長什麼樣子」。如果第二個團隊也要一套一樣的 Lambda + API Gateway + DynamoDB + IAM，在沒有 module 的情況下，唯一的做法是整份複製貼上——這代表任何一次修正都要在每一份複製品裡重複套用一次，很容易漏改、產生分歧。

**決策：拆出 `modules/app_service`**，把「一個標準服務長什麼樣子」的定義收斂到單一位置。團隊呼叫端只需要提供參數（`owner`、DynamoDB 容量設定等），不需要重新理解 Lambda/API Gateway/IAM 怎麼接線，模組內部的任何修正也只需要改一個地方，所有呼叫端下次 apply 就會套用到。這也是 module 相對於「共用一份範例程式碼、各自複製修改」的根本差異：module 是唯一事實來源，複製貼上不是。

## 3. 保留 dev/prod 分離的背景，以及為什麼不把 environment 放進 resource prefix

分開 dev/prod 的理由跟這次多團隊的動機是同一件事的不同維度：不管是團隊或環境，本質上都是「多個使用情境共用同一套基礎設施定義，但彼此的資源、blast radius 不該互相影響」。dev 的實驗性變更、錯誤的 apply、甚至誤 destroy，都不該波及 prod 的真實流量與資料——這也是 Step 5（多環境與生命週期管理）會替 prod 的 DynamoDB table 額外加 `prevent_destroy` 的原因。

**前提：`name_prefix` 刻意不包含 `environment`。** 這不是漏寫，而是假設 dev/prod 部署在不同的 AWS 帳號（或不同的 LocalStack instance），不會共用同一個帳號。account-per-environment 本身就是天生的隔離邊界：不只是命名不會撞，IAM 權限邊界、API quota、誤操作的 blast radius 都完全分開，比起在同一帳號內單純用字串前綴區隔更安全、更徹底。也因為這個前提，`environment` 不需要參與命名——它只出現在 `local.common_tags` 裡供追蹤用，不影響資源實際的名稱。

如果之後這個前提不成立（例如為了省成本，用單一 sandbox 帳號同時放 dev/staging/prod），`name_prefix` 就必須改成 `"${var.owner}-${var.environment}"`，把 `environment` 也算進去，否則會在同一帳號內撞名。

## 4. 確保 state 分開，為什麼這樣做決策

**選項 1**：在同一個 root 裡放多個 `module` block（每個團隊一個，例如 `module "app_service_team_alpha"`、`module "app_service_team_beta"`），全部共用同一份 state。
缺點：所有團隊共用同一個 state file/lock，一個團隊在 apply 時會卡住另一個團隊的 apply；這個共用的 root 檔案會變成所有團隊共同編輯的地方，PR 衝突機率變高，任何一個團隊的設定錯誤都可能讓整個 `plan`/`apply` 失敗，波及其他團隊。

**選項 2（採用）**：每個團隊各自一份 root module（`envs/dev/teamalpha/`、`envs/dev/teambeta/`），各自呼叫同一個 `modules/app_service`、各自獨立的 state 檔案。

**決策：採用選項 2。** 理由：
- Blast radius 隔離——一個團隊的 apply/destroy 不會影響到其他團隊的資源或 state lock。
- 更貼近這個平台的定位：平台提供標準模組，各團隊各自管理自己那份基礎設施的生命週期，而不是共用一份誰都能改的設定檔。

這個決策已經用 `teamalpha`、`teambeta` 兩個團隊實際 apply 驗證過：兩者的資源命名（`teamalpha-terrals-*` / `teambeta-terrals-*`）、DynamoDB table、S3 bucket 互不撞名，各自的 state 完全獨立，其中一個團隊的 apply 不會出現在另一個團隊的 state 裡；IAM policy 的 `Resource` 也各自鎖定在自己的 DynamoDB table ARN，team 之間連權限都是隔離的。
