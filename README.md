# Terrals — Self-Service App Platform（Terraform × LocalStack）

Terrals（Terraform + LocalStack）是一個示範「self-service 內部平台」概念的 Terraform 專案：目標是打造一套讓其他開發團隊可以自助部署服務的標準化基礎設施，而不是零散的單一資源範例。所有雲端資源都跑在本機的 [LocalStack](https://www.localstack.cloud/) 上，不需要真的 AWS 帳號、也不會產生費用。

這個 repo 是逐步建置的：每個階段在既有結構上疊加功能，commit 歷史會完整呈現這個平台從單一資源長成一個完整、可部署、有 CI/CD 的專案的過程。

## 設計決策：為什麼是 Lambda + API Gateway，而不是 EC2/VPC？

多數 Terraform 教材會用 EC2/VPC 當主要情境，但 LocalStack 的免費版對 EC2 只做到 API 層級模擬——資源會被建立、可以查得到，但不會真的開一台機器，無法把服務跑在上面。

Lambda + API Gateway 則是 LocalStack 免費版支援最完整的服務之一：LocalStack 會用 Docker 真的執行上傳的程式碼，API Gateway 也會把 HTTP request 真實轉發進 Lambda 並回傳結果。因此這個平台選擇 Lambda/API Gateway 作為實際可部署的服務層，VPC/EC2/網路設計則作為獨立模組保留（Platform Engineer 的工作仍然離不開網路基礎），但不強行接線到一個「不會真的執行」的運算資源上。

## 架構

```
terrals/
├── .gitignore
├── README.md
├── docker-compose.yml              # LocalStack
├── bootstrap/                      # remote state 用的 S3 bucket + DynamoDB lock table
├── modules/
│   ├── networking/                 # VPC/subnet/route table/security group（獨立模組，未接線到服務）
│   └── app_service/                # 核心模組：Lambda + API Gateway + DynamoDB + IAM
├── envs/
│   ├── dev/
│   └── prod/                       # lifecycle 保護、版本管理與環境隔離
└── .github/workflows/              # terraform-ci.yml
```

`envs/<name>/` 從一開始就是各環境程式碼的家，state 依環境用不同的 backend key 完全隔離。`modules/networking` 是獨立的 IaC/網路練習，`modules/app_service` 才是平台實際對外提供的自助部署單元。

## 快速開始

```bash
docker-compose up -d
curl http://localhost:4566/_localstack/health
```

回應中列出的服務都是 `available` 即代表 LocalStack 已就緒。`docker-compose down` 可以隨時關閉環境，資料不會留在任何真實雲端帳號上。

常用驗證指令：

```bash
aws --endpoint-url=http://localhost:4566 s3 ls
aws --endpoint-url=http://localhost:4566 dynamodb list-tables
aws --endpoint-url=http://localhost:4566 lambda list-functions
aws --endpoint-url=http://localhost:4566 apigateway get-rest-apis
```

> LocalStack 的 `latest` image 自 2026-03-23 起併入 Pro 版並強制要求 `LOCALSTACK_AUTH_TOKEN`，本專案的 [docker-compose.yml](docker-compose.yml) 已釘在合併前最後一版 Community image（`4.14.0`），不需要任何帳號或 token。

---

## 建置歷程

### 階段 1 — 起手式：第一個資源（`envs/dev/`）

Provider 設定指向 LocalStack 而非真實 AWS：`versions.tf` 釘住 `required_version`／`required_providers`；`provider.tf` 用假憑證（`test`/`test`）+ `endpoints {}` block 導向 `http://localhost:4566`，並關閉 `skip_credentials_validation`／`skip_metadata_api_check`／`skip_requesting_account_id` 這類只有真實 AWS 才需要的檢查；`main.tf` 建立一個 S3 bucket，之後用來存放 Lambda 部署包。

**驗證方式**：`terraform apply` 後 `aws s3 ls` 看得到 bucket；`terraform destroy` 後資源真的消失——這是 Terraform 銷毀語意最基本的體現：destroy 不是封存，是直接呼叫 API 刪除。

### 階段 2 — 參數化與標籤規範

新增 `variables.tf`／`terraform.tfvars`／`outputs.tf`，把寫死的值改成變數；新增一張 DynamoDB table 供服務儲存資料；用 `locals` 定義一組共用標籤（`Project`／`Environment`／`Owner`／`ManagedBy = "terraform"`）套用到所有資源，這是多數公司內部規範資源歸屬與成本歸因的標準做法。

**驗證方式**：只改 `terraform.tfvars` 就能改變要建立的資源命名，不用碰任何 `.tf` 邏輯。

### 階段 3 — Module 化（`modules/`）

拆出兩個可重用模組：

- **`modules/app_service`**：核心模組。一支 Lambda function、一個指向它的 API Gateway REST API、一個最小權限的 IAM role（只給必要的 DynamoDB 存取，不用萬用字元），輸出 API invoke URL。
- **`modules/networking`**：VPC、public/private subnet、route table、security group，作為獨立的網路知識模組，不接線到 `app_service`。

`envs/dev/main.tf` 改為呼叫這兩個模組。

**驗證方式**：`terraform apply` 完成後，`curl` module 輸出的 invoke URL 能拿到真實的 HTTP 回應——這是整個平台第一次「部署了一個服務、也真的打得到它」的里程碑。

### 階段 4 — Remote State + Locking（`bootstrap/`）

`bootstrap/` 用本機 state（刻意不指定 backend，避免自我依賴的雞生蛋問題）建立 remote state 用的 S3 bucket（開 versioning）與 DynamoDB lock table（hash key 為 `LockID`）。`envs/dev` 新增 `backend.tf` 指向這組 backend，`key` 依環境區分（例如 `envs/dev/terraform.tfstate`），並透過 `terraform init -migrate-state` 把既有 state 搬遷過去。

**驗證方式**：migrate 後 `terraform plan` 不應顯示任何資源需要重建；S3 bucket 內能看到 `.tfstate` 檔案；對同一份 state 同時執行兩個 `terraform apply` 時，DynamoDB lock 會擋下第二個請求。

### 階段 5 — 多環境與生命週期管理（`envs/prod/`）

`envs/prod` 沿用相同結構，改用獨立的 tfvars 與 backend key，與 `dev` 完全隔離。這個階段聚焦在 Terraform「建立之後」的行為：

- `lifecycle { prevent_destroy = true }` 保護 prod 的 DynamoDB table，避免誤刪。
- `create_before_destroy = true` 套用在 API Gateway deployment 或 Lambda alias 上，示範零停機替換。
- `ignore_changes` 處理由平台外機制修改、不該被每次 plan 標記為 diff 的欄位。
- **Serverless 特有的回收議題**：Lambda 每次部署會產生新的 published version，用 `aws_lambda_alias`（例如 `live`）指向目前版本；舊版本會持續累積，Terraform 不會自動清理——這正是「Terraform 沒有內建垃圾回收」的具體例子。
- AWS 原生層級的資源回收（與 Terraform 的 lifecycle 是不同層次的機制）：S3 bucket 的 `lifecycle_rule`（過期版本清除、中止未完成的 multipart upload）、DynamoDB table 的 TTL 屬性。

**核心觀念**：State 是 Terraform 唯一的「誰該存在」真相來源，不在 state 裡卻真實存在雲端的孤兒資源，Terraform 不會主動發現或清除，這也是業界會搭配 `driftctl`／`cloud-nuke` 之類工具做稽核的原因。

### 階段 6 — CI/CD 與安全掃描（`.github/workflows/`）

`terraform-ci.yml` 在 PR 觸發時執行 `fmt -check`／`validate`／`tflint`／`checkov`／`plan`；`.pre-commit-config.yaml` 讓同樣的檢查在 commit 前就先攔截。因為這個平台部署的服務是真的能執行的，CI 額外加入一個 smoke test：`apply` 到暫時環境後直接 `curl` API Gateway 端點驗證回應內容；並在 PR 關閉時觸發對應的 `terraform destroy`（`on: pull_request: types: [closed]`），實踐「用完即丟」的 ephemeral environment 模式——這是銷毀/回收機制在 CI/CD 層級的落地。

---

完成以上六個階段後，這個 repo 具備完整結構、remote state、多環境隔離、CI/CD、安全掃描，以及一個真正可以部署並存取的服務，涵蓋了 Platform Engineer 職缺所需的核心 Terraform 實踐。
