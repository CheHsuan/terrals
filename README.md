# Self-Service App Platform（Terraform × LocalStack 練習）

這是一個為了準備 **Platform Engineer** 職缺而設計的 Terraform 練習專案。目標不是做一堆零散的 toy 範例，而是**用一個真實的 repo，一步一步把它長成一個公司內部平台團隊會交出來的東西**：一個讓其他開發團隊可以「self-service」部署自己服務的標準化基礎設施平台。

所有雲端資源都跑在本機的 [LocalStack](https://www.localstack.cloud/) 上，不需要真的 AWS 帳號、不會產生任何費用。

## 為什麼選 Lambda + API Gateway 當主線？

一開始考慮過用 EC2/VPC 當主要情境（很多 Terraform 教材都這樣做），但 LocalStack 的免費版對 EC2 只做到「API 層級模擬」——資源會被建立、可以用 `aws ec2 describe-instances` 查到，但**不會真的開一台機器**，沒辦法 SSH 進去、沒辦法真的把服務跑在上面。

Lambda + API Gateway 則是 LocalStack 免費版最紮實、最完整支援的功能之一：LocalStack 會用 Docker 真的把你上傳的程式碼**執行起來**，API Gateway 也會真的把 HTTP request 轉進 Lambda 並回傳真實回應。所以這個練習選擇 Lambda/API Gateway 當「平台真正能部署的服務」，VPC/EC2/網路設計則保留成獨立的模組練習——因為 Platform Engineer 仍然需要懂網路，但這裡不強求它要接到一個「真的在跑」的服務上。

## 最終目標結構

這個 repo 會分 6 個步驟逐步長成下面這個樣子（不是一次生成，是一步一步用 commit 疊上去）：

```
terrals/
├── .gitignore
├── README.md
├── docker-compose.yml              # LocalStack
├── bootstrap/                      # [Step 4] remote state 用的 S3 bucket + DynamoDB lock table
├── modules/                        # [Step 3]
│   ├── networking/                 # VPC/subnet/route table/security group（獨立練習，不接線到服務）
│   └── app_service/                # ★ 主線：Lambda + API Gateway + DynamoDB + IAM，真的可以部署並 curl 得到回應
├── envs/
│   ├── dev/                        # [Step 1] 就存在，逐步長出 variables/backend/module 呼叫
│   └── prod/                       # [Step 5] 示範 lifecycle 保護、版本管理與環境隔離
└── .github/workflows/              # [Step 6] terraform-ci.yml
```

## 環境準備

```bash
docker-compose up -d
curl http://localhost:4566/_localstack/health
```

看到回應裡列出的服務都是 `"available"` 或 `"running"` 就代表 LocalStack 準備好了。之後每個步驟都是在 LocalStack 上操作，練完隨時可以 `docker-compose down` 關掉，資料不會留在真的 AWS 上——這件事本身也是這個練習想傳達的重點之一：**用完即丟、乾淨回收**。

常用驗證指令（之後每個步驟都會用到）：

```bash
aws --endpoint-url=http://localhost:4566 s3 ls
aws --endpoint-url=http://localhost:4566 dynamodb list-tables
aws --endpoint-url=http://localhost:4566 lambda list-functions
aws --endpoint-url=http://localhost:4566 apigateway get-rest-apis
```

（如果沒裝 `aws` CLI，之後我會協助你安裝，或改用 LocalStack 的 `awslocal` 包裝指令。）

## 怎麼跟這個計畫互動

每個 Step 都不會有現成的 `.tf` 答案——由你自己寫。流程是：

1. 讀這份 README 裡該 Step 的任務描述與驗收標準。
2. 自己動手寫 Terraform code、跑 `terraform init/plan/apply`。
3. 用上面的驗證指令 / `curl` 確認資源真的照你預期建立。
4. 跟我說「這步做完了」，我會幫你 review code、抓問題、補充你可能沒注意到的公司標準作法或坑，再解鎖下一步的細節。

---

## 學習路線圖

### Step 1 — 起手式：第一個資源（`envs/dev/`）

**學習目標**：搞懂 Terraform 最基本的工作循環，以及 provider 怎麼指向 LocalStack 而不是真的 AWS。

**要新增的檔案**：`envs/dev/versions.tf`、`envs/dev/provider.tf`、`envs/dev/main.tf`

**任務**：
- 在 `versions.tf` 宣告 `required_version` 與 `required_providers`（`hashicorp/aws`），都要釘版本。
- 在 `provider.tf` 設定 AWS provider，用假的 credentials（`access_key`/`secret_key` 隨便填，例如 `test`/`test`），region 用 `us-east-1`，並用 `endpoints { s3 = "http://localhost:4566" }` 這類設定把 S3（之後其他服務也是）導向 LocalStack。記得要設 `skip_credentials_validation`、`skip_metadata_api_check`、`skip_requesting_account_id` 之類的旗標（LocalStack 不是真的 AWS，這些檢查會失敗）。
- 在 `main.tf` 建一個 S3 bucket（之後會拿來放 Lambda 部署包，先建起來就好）。

**該查的關鍵字**：`terraform provider aws endpoints block`、`terraform required_providers`、`terraform init/plan/apply/destroy`。

**驗收標準**：
- `terraform apply` 成功。
- `aws --endpoint-url=http://localhost:4566 s3 ls` 看得到你的 bucket。
- `terraform destroy` 之後，再跑一次上面的指令，bucket 要消失——親眼確認「銷毀」這件事在 Terraform 裡是怎麼發生的：它不是把資源關掉封存，是真的呼叫 API 把它刪掉。

---

### Step 2 — 參數化與標籤規範

**學習目標**：學會用 variables 讓 code 可重用、學會公司常見的強制標籤（tagging）規範。

**要新增的檔案**：`envs/dev/variables.tf`、`envs/dev/terraform.tfvars`、`envs/dev/outputs.tf`

**任務**：
- 把 Step 1 寫死的值（bucket 名稱、region 等）改成 `variable`，`terraform.tfvars` 填實際值。
- 新增一個 DynamoDB table（之後服務要用來存資料），table 名稱、hash key 等也用變數控制。
- 用 `locals` 定義一組共用標籤（`Project`、`Environment`、`Owner`、`ManagedBy = "terraform"`），套用在所有資源上。
- 加 `outputs.tf`，把 bucket name、table name 輸出。

**該查的關鍵字**：`terraform variable validation`、`terraform locals`、`terraform output`、AWS 資源 tagging 標準作法。

**驗收標準**：`terraform plan` 不用改任何 `.tf` 檔案本身、只改 `terraform.tfvars` 就能改變要建立的資源名稱；`terraform output` 能印出 bucket/table 名稱。

---

### Step 3 — Module 化（新增 `modules/`）

**學習目標**：把資源封裝成可重用模組，體會「self-service 平台模組」的設計方式。

**要新增/修改的檔案**：
- `modules/app_service/{main.tf,variables.tf,outputs.tf}`：★ 主線模組。內容包含：
  - 一支簡單的 Lambda function（先用最小的 handler 就好，例如回傳固定字串，或讀寫 Step 2 建的 DynamoDB table）。
  - 一個 API Gateway（REST API），設一個 route/method 指到這支 Lambda。
  - Lambda 執行用的 IAM role（用最小權限，只給它需要的 DynamoDB 權限，不要用 `*`）。
  - module 要輸出 API 的 invoke URL。
- `modules/networking/{main.tf,variables.tf,outputs.tf}`：VPC、public/private subnet、route table、security group。這個先當獨立模組練習，**不需要**接到 `app_service` 上。
- `envs/dev/main.tf` 改成呼叫這兩個 module（`networking` 可以先呼叫但不用真的被誰用到；`app_service` 才是真正串起服務的部分）。

**該查的關鍵字**：`terraform module source`、`aws_lambda_function`、`aws_api_gateway_rest_api` / `aws_api_gateway_deployment`、`aws_iam_role` + `aws_iam_role_policy`（least privilege）。

**驗收標準（這步的重點）**：
- `terraform apply` 完成後，從 `terraform output` 拿到 API 的 invoke URL。
- 執行 `curl <invoke-url>`，要拿到**真實的 HTTP 回應**（不是模擬、是你的 Lambda 程式碼真的執行後回傳的結果）。
- 這是整個計畫第一次「自己部署了一個服務、也真的打得到它」的里程碑。

---

### Step 4 — Remote State + Locking（新增 `bootstrap/`）

**學習目標**：搞懂為什麼公司不會把 state 放在本機、state locking 解決什麼問題。

**要新增的檔案**：`bootstrap/{main.tf,variables.tf,outputs.tf,versions.tf}`、`envs/dev/backend.tf`

**任務**：
- `bootstrap/` 用**本機 state**（不指定 backend）建立一個 S3 bucket（拿來當 remote state 存放處，記得開 versioning）跟一個 DynamoDB table（拿來做 lock，hash key 用 `LockID`）。
- 為什麼 bootstrap 要跟 `envs/dev` 分開、且自己用 local state？想一下：如果 state 的 backend 資源本身也放在同一份要用這個 backend 的 state 裡，會有什麼雞生蛋問題？
- `envs/dev` 新增 `backend.tf`，設定 `backend "s3"`，指向 bootstrap 建出來的 bucket/table，`key` 用類似 `envs/dev/terraform.tfstate` 的路徑（為之後多環境鋪路）。
- 跑 `terraform init -migrate-state` 把 Step 1-3 的 local state 搬過去。

**該查的關鍵字**：`terraform backend s3`、`dynamodb_table` for state locking、`terraform init -migrate-state`、`terraform state list` / `terraform state mv`、`terraform plan -refresh-only`（drift 偵測）。

**驗收標準**：
- `terraform plan` 在 migrate 之後不應該顯示要重建任何既有資源（代表 state 搬移正確）。
- 手動去 LocalStack 查 S3 bucket，能看到裡面真的有一個 `.tfstate` 檔案。
- 試著同時在兩個 terminal 對同一個 state 跑 `terraform apply`，觀察 DynamoDB lock 擋下第二個的行為。

---

### Step 5 — 多環境與生命週期／回收機制（新增 `envs/prod/`）

**學習目標**：這是你最在意的部分——Terraform「建立之後」的世界怎麼運作。

**要新增/修改的檔案**：`envs/prod/`（複製 `envs/dev` 的結構，改 tfvars 與 backend key）

**任務**：
1. 複製出 `envs/prod`，用不同的 `terraform.tfvars`（例如不同的資源命名前綴），`backend.tf` 的 `key` 要跟 dev 不同（環境間 state 要完全隔離）。
2. 在 prod 的 DynamoDB table 加上：
   ```hcl
   lifecycle {
     prevent_destroy = true
   }
   ```
   然後**故意**嘗試 `terraform destroy` 或移除該 resource block 再 apply，看 Terraform 怎麼擋下你。
3. 找一個資源（例如 API Gateway 的 deployment，或 Lambda alias）示範 `create_before_destroy = true`，想一下這個設定解決的是什麼問題（新資源建好才砍舊的，避免服務中斷的空窗期）。
4. 示範一個 `ignore_changes` 的情境（例如某個之後可能被平台外的機制改動的欄位）。
5. **Serverless 專屬的回收案例**：Lambda 每次部署新程式碼會產生新的 published version，善用 `aws_lambda_alias`（例如一個叫 `live` 的 alias）指向目前要用的版本。動手想一下：舊版本會一直留著佔空間，Terraform **不會自動幫你清掉**它們——這正是「Terraform 沒有垃圾回收」的具體例子。
6. AWS 原生層級的回收機制（跟 Terraform 的 lifecycle 是兩回事，這些是 AWS 自己執行的）：
   - S3 bucket 加 `lifecycle_rule`：過期版本清除（`noncurrent_version_expiration`）、中止未完成的 multipart upload（`abort_incomplete_multipart_upload`）。
   - DynamoDB table 加 TTL 屬性，示範資料到期自動刪除。

**該查的關鍵字**：`terraform lifecycle meta-argument`、`prevent_destroy` / `create_before_destroy` / `ignore_changes`、`aws_lambda_alias`、`aws_s3_bucket_lifecycle_configuration`、`aws_dynamodb_table` TTL、`driftctl` / `cloud-nuke`（業界拿來抓孤兒資源用的工具，這裡不用實作，但要知道有這個問題存在）。

**重點觀念（會在你完成後跟你一起確認）**：
- Terraform **沒有自動垃圾回收**。State 是唯一的「誰該存在」真相來源；不在 state 裡但實際存在雲端的資源（孤兒資源），Terraform 完全不會發現、也不會清掉。
- `lifecycle` 三個 meta-argument 管的是「Terraform 執行 apply/destroy 時的行為」，跟「AWS 資源自己會不會過期/自動清理」（S3 lifecycle rule、DynamoDB TTL）是兩個完全不同層次的機制，很多人會搞混。

---

### Step 6 — CI/CD 與安全掃描（新增 `.github/workflows/`）

**學習目標**：把前 5 步練的東西變成一個團隊真的會用的自動化流程。

**要新增的檔案**：`.github/workflows/terraform-ci.yml`、`.pre-commit-config.yaml`、`.tflint.hcl`

**任務**：
- 寫一個 GitHub Actions workflow，在 PR 觸發時跑：`terraform fmt -check`、`terraform validate`、`tflint`、`checkov`（或 `tfsec`）安全掃描、`terraform plan`。
- 加 `.pre-commit-config.yaml`，讓上面幾個檢查在本機 commit 前就先擋下來，不用等 CI。
- **因為這次的服務是真的能跑**：加一個步驟，在暫時的環境上 `apply` 完之後，真的用 `curl` 打 API Gateway 的 URL，檢查回應內容符合預期（一個真實的 smoke test，而不只是 `terraform plan` 沒有錯誤而已）。
- 設計「PR 關閉時自動 `terraform destroy` 這個暫時環境」的 workflow（`on: pull_request: types: [closed]`）——這是很多平台團隊處理「用完即丟」測試環境的標準作法，直接回應銷毀/回收機制在 CI/CD 層級的實踐。

**該查的關鍵字**：GitHub Actions `services:` 跑 LocalStack container、`terraform fmt -check` / `validate` exit code、`tflint`、`checkov`、ephemeral environment pattern。

**驗收標準**：PR 開一個小改動，觀察 workflow 自動跑起 fmt/validate/lint/scan/plan；模擬關閉 PR，確認 destroy workflow 會被觸發。

---

完成六個步驟後，這個 repo 就是一個結構完整、有 remote state、有多環境、有 CI/CD、有安全掃描、也真的能部署一個可以打得到的服務的 Terraform 專案——可以直接放進履歷或作品集，也涵蓋了 Platform Engineer 職缺會考的大部分核心概念。
