# Terrals — 共用基礎設施平台（Terraform × LocalStack）

Terrals（Terraform + LocalStack）是一個示範「共用基礎設施平台」概念的 Terraform 專案：目標是打造一套讓多個開發團隊共用同一套標準化基礎設施部署服務的方式，而不是零散的單一資源範例。所有雲端資源都跑在本機的 [LocalStack](https://www.localstack.cloud/) 上，不需要真的 AWS 帳號、也不會產生費用。

這個 repo 是逐步建置的：每個階段在既有結構上疊加功能，commit 歷史會完整呈現這個平台從單一資源長成一個完整、可部署、有 CI/CD 的專案的過程。

## 設計決策：為什麼是 Lambda + API Gateway，而不是 EC2/VPC？

多數 Terraform 教材會用 EC2/VPC 當主要情境，但 LocalStack 的免費版對 EC2 只做到 API 層級模擬——資源會被建立、可以查得到，但不會真的開一台機器，無法把服務跑在上面。

Lambda + API Gateway 則是 LocalStack 免費版支援最完整的服務之一：LocalStack 會用 Docker 真的執行上傳的程式碼，API Gateway 也會把 HTTP request 真實轉發進 Lambda 並回傳結果。因此這個平台選擇 Lambda/API Gateway 作為實際可部署的服務層，VPC/EC2/網路設計則作為獨立模組保留（工程師的工作仍然離不開網路基礎），但不強行接線到一個「不會真的執行」的運算資源上。

## 架構

```
terrals/
├── .gitignore
├── README.md
├── docker-compose.yml              # LocalStack
├── bootstrap/                      # remote state 用的 S3 bucket + DynamoDB lock table
├── modules/
│   └── app_service/                # 核心模組：Lambda + API Gateway + DynamoDB + IAM
├── envs/
│   ├── dev/
│   └── prod/                       # lifecycle 保護、版本管理與環境隔離
└── .github/workflows/              # terraform-ci.yml
```

`envs/<name>/` 從一開始就是各環境程式碼的家，state 依環境用不同的 backend key 完全隔離。`modules/app_service` 是平台實際提供給各團隊共用的服務模組。

## 快速開始

```bash
docker-compose up -d
curl http://localhost:4566/_localstack/health
```

回應中列出的服務都是 `available` 即代表 LocalStack 已就緒。`docker-compose down` 可以隨時關閉環境，資料不會留在任何真實雲端帳號上。

LocalStack 不驗證憑證是否有效，但 AWS CLI 與 Terraform 的 AWS provider 都要求「有填」東西才會送出請求。假憑證一律透過環境變數提供，不寫進任何 `.tf` 或設定檔：

```bash
export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_DEFAULT_REGION=us-east-1
```

常用驗證指令：

```bash
aws --endpoint-url=http://localhost:4566 s3 ls
aws --endpoint-url=http://localhost:4566 dynamodb list-tables
aws --endpoint-url=http://localhost:4566 lambda list-functions
aws --endpoint-url=http://localhost:4566 apigateway get-rest-apis
```

> LocalStack 的 `latest` image 自 2026-03-23 起併入 Pro 版並強制要求 `LOCALSTACK_AUTH_TOKEN`，本專案的 [docker-compose.yml](docker-compose.yml) 已釘在合併前最後一版 Community image（`4.14.0`），不需要任何帳號或 token。

## 常用 Terraform 指令

每個階段都會反覆用到這些指令，先熟悉一輪：

### 基本工作流程

| 指令 | 用途 |
|---|---|
| `terraform init` | 初始化工作目錄、下載 provider。初次使用、新增 module 或改了 backend 設定後都要重跑 |
| `terraform fmt` | 依官方風格自動排版 `.tf` 檔案 |
| `terraform validate` | 檢查語法與內部參照是否正確，不會連線到雲端 |
| `terraform plan` | 比對「程式碼描述的樣子」跟「目前實際狀態」，印出將要變更的內容，不會真的動手 |
| `terraform apply` | 執行 `plan` 算出來的變更，實際建立／修改／刪除資源；會先跳出確認，`-auto-approve` 可跳過 |
| `terraform destroy` | 把這份 state 管理的資源全部刪除 |

### 檢查與除錯

| 指令 | 用途 |
|---|---|
| `terraform show` | 用人看得懂的格式印出目前 state 內容 |
| `terraform output` | 印出 `outputs.tf` 定義的輸出值 |
| `terraform plan -refresh-only` | 只跟雲端同步實際狀態、找出 drift（有人手動改了雲端上的資源），不會產生變更計畫 |
| `terraform console` | 互動式介面，可即時算 expression、看變數／local 的值，除錯很好用 |

### State 管理

| 指令 | 用途 |
|---|---|
| `terraform state list` | 列出這份 state 目前追蹤的所有資源 |
| `terraform state show <resource>` | 看某個資源在 state 裡記錄的完整屬性 |
| `terraform state mv <old> <new>` | 幫某個資源在 state 裡改名／搬位置（例如重構成 module 之後），不會動到實際雲端資源 |
| `terraform state rm <resource>` | 把某個資源從 state 移除，但不刪除它在雲端的實體——讓 Terraform 忘記管它 |
| `terraform import <resource> <id>` | 把雲端上手動建立、還沒被 Terraform 管理的既有資源，接管進 state |

### 其他實用指令與參數

| 指令／參數 | 用途 |
|---|---|
| `terraform apply -replace=<resource>` | 強制重建某個資源（取代舊版的 `terraform taint`） |
| `terraform plan -var-file=xxx.tfvars` | 指定要套用哪一份 tfvars |
| `terraform apply -target=<resource>` | 只針對單一資源執行，除錯用，不建議日常依賴 |
| `terraform providers` | 列出這個專案用到哪些 provider 及版本 |
| `terraform workspace list` / `new` / `select` | 管理 workspace；這個專案改用 `envs/<name>/` 資料夾分環境、不用 workspace，但這是業界另一種常見做法，值得知道 |

## 安全與敏感資訊處理原則

這幾條原則貫穿所有階段，不是單一步驟的事：

- **憑證不進版控**：無論真假，AWS 憑證一律透過環境變數提供，任何 `.tf`／`.tfvars` 檔案裡都不會出現 access key 或 secret 字面值。
- **State 檔案視為機密資料**：Terraform state 常以明文記錄資源屬性，某些服務的回傳值本身就帶有機敏資訊。因此 remote state 用的 S3 bucket 一定要加密、封鎖公開存取、並限制存取權限——state 外洩的殺傷力不亞於憑證外洩，卻常被忽略。
- **敏感變數／輸出要明確標記**：任何可能帶有機敏值的 `variable`／`output` 都加上 `sensitive = true`，避免值被印進 `terraform plan`／`apply` 的終端機輸出或 CI log。
- **S3 bucket 一律封鎖公開存取**：不管是應用程式資料還是 state，每個 S3 bucket 都明確加上 `aws_s3_bucket_public_access_block`，不依賴「預設不公開」的假設。
- **IAM 最小權限**：每個角色只給它需要的資源與動作，不用萬用字元（`*`），降低單一憑證外洩後的擴散範圍。
- **CI 不留長效憑證**：LocalStack 是假環境，CI 用寫死的 `test`/`test` 沒有風險；但這裡示範的是「憑證來自環境變數、不寫死在程式碼」的模式，之後接上真實雲端時，正確做法是換成 OIDC federation（GitHub Actions 原生支援直接對 AWS 換發短效憑證），不需要把長效 access key 存成 repo secret。

---

## 建置歷程

### 階段 1 — 起手式：第一個資源（`envs/dev/`）

運用情境：
✅ 平台需要一個地方存放要交付給服務的部署產物（Lambda 部署包）。
✅ 建置 1 組 S3 Bucket，作為之後 Lambda function 程式碼包的存放位置。
👉 這階段刻意只做「建立 → 確認存在 → 銷毀 → 確認消失」的最小循環，先確保 provider 有正確指向 LocalStack，不會不小心打到真的 AWS。

Provider 設定指向 LocalStack 而非真實 AWS：`versions.tf` 釘住 `required_version`／`required_providers`；`provider.tf` 只設定 `endpoints {}` block 導向 `http://localhost:4566`，並關閉 `skip_credentials_validation`／`skip_metadata_api_check`／`skip_requesting_account_id` 這類只有真實 AWS 才需要的檢查——**憑證本身不寫進 `.tf`**，即使是 `test`/`test` 這種假值，也是透過 `AWS_ACCESS_KEY_ID`／`AWS_SECRET_ACCESS_KEY` 環境變數提供，provider 會自動讀取。這個習慣從練習階段就養成，之後接上真實帳號時不會有把憑證寫進版控的風險。`main.tf` 建立一個 S3 bucket，之後用來存放 Lambda 部署包，並加上 `aws_s3_bucket_public_access_block` 明確封鎖公開存取——即使是練習環境，這個設定也從第一個資源就內建進去，不是之後才補。

**驗證方式**：`terraform apply` 後 `aws s3 ls` 看得到 bucket；`terraform destroy` 後資源真的消失——這是 Terraform 銷毀語意最基本的體現：destroy 不是封存，是直接呼叫 API 刪除。

### 階段 2 — 參數化與標籤規範

運用情境：
✅ 服務需要一張資料表存放使用者提交的資料。
✅ 建置 1 組 DynamoDB Table，hash key 用唯一識別碼。
✅ 所有資源套用公司強制標籤（Project/Environment/Owner/ManagedBy），供財務與稽核追蹤資源歸屬。
👉 資源命名與規模改用 tfvars 控制，同一份 `.tf` 邏輯之後能直接套用到不同環境，不用改程式碼本身。
👉 任何未來可能帶有機敏值的變數／輸出都加上 `sensitive = true`，避免它被印進 `terraform plan`／`apply` 的終端機輸出。

新增 `variables.tf`／`terraform.tfvars`／`outputs.tf`，把寫死的值改成變數；新增一張 DynamoDB table 供服務儲存資料；用 `locals` 定義一組共用標籤（`Project`／`Environment`／`Owner`／`ManagedBy = "terraform"`）套用到所有資源，這是多數公司內部規範資源歸屬與成本歸因的標準做法。

**驗證方式**：只改 `terraform.tfvars` 就能改變要建立的資源命名，不用碰任何 `.tf` 邏輯。

👉 這個階段把幾個 resource label 從 kebab-case 統一改成 snake_case，過程中意外踩到一個很值得記錄的問題：即使 `bucket = "..."`／`name = "..."` 這些實際欄位完全沒變，單純改 resource label 也會讓 `terraform plan` 判定成整個 destroy + create——因為 state 是用 resource address 當 key，不是用雲端上的實際身份比對。這個問題、原因，以及三種處理方式（`moved` block／`terraform state mv`／接受重建）的實測比較，整理在 [`docs/renaming-resources.md`](docs/renaming-resources.md)。

### 階段 3 — Module 化（`modules/`）

運用情境：
✅ 多個開發團隊要能共用同一套標準模組部署對外服務，不需要各自研究 Lambda/API Gateway/IAM 怎麼串起來。
✅ 平台提供 1 個標準模組（`app_service`），輸入服務名稱與資料表設定，就能拿到一組可運作的 API。
✅ Lambda 執行角色僅授權存取自己需要的 DynamoDB 資料表，不使用萬用權限。
👉 這一步的驗收基準是「`curl` 得到真的服務回應」，不是 `terraform apply` 沒報錯而已——因為 LocalStack 真的會執行你的程式碼。

拆出一個可重用模組：

- **`modules/app_service`**：核心模組。一支 Lambda function、一個指向它的 API Gateway REST API、一個最小權限的 IAM role（只給必要的 DynamoDB 存取，不用萬用字元），輸出 API invoke URL。

`envs/dev/<team>/main.tf`（例如 `envs/dev/teamalpha/`、`envs/dev/teambeta/`）各自一份 root，各自呼叫這個模組、各自獨立的 state。

**驗證方式**：`terraform apply` 完成後，`curl` module 輸出的 invoke URL 能拿到真實的 HTTP 回應——這是整個平台第一次「部署了一個服務、也真的打得到它」的里程碑。

多團隊共用同一個模組時的命名與 state 隔離策略，記錄在 [`docs/multi-team-app-service.md`](docs/multi-team-app-service.md)。

### 階段 4 — Remote State + Locking（`bootstrap/`）

運用情境：
✅ 多人共同維運這個平台，state 不能只放在某人的筆電上。
✅ 建置 1 組 S3 Bucket 供 remote state 存放（開 versioning），1 組 DynamoDB Table 做 state lock。
✅ 兩人同時對同一份環境跑 apply 時，其中一人會被 lock 擋下，不會讓 state 損毀。
👉 這組 backend 資源要在獨立的 `bootstrap` 專案裡先用 local state 建出來，避免「用 S3 backend 的 state 本身，放在還沒建出來的 S3 bucket 裡」的雞生蛋問題。
👉 State bucket 開啟預設加密（`server_side_encryption_configuration`）並封鎖公開存取，因為 state 裡的資源屬性可能帶有機敏值，外洩風險不亞於憑證外洩。

`bootstrap/` 用本機 state（刻意不指定 backend，避免自我依賴的雞生蛋問題）建立 remote state 用的 S3 bucket（開 versioning、預設加密、封鎖公開存取）與 DynamoDB lock table（hash key 為 `LockID`）。`envs/dev` 新增 `backend.tf` 指向這組 backend，`key` 依環境區分（例如 `envs/dev/terraform.tfstate`），並透過 `terraform init -migrate-state` 把既有 state 搬遷過去。

**驗證方式**：migrate 後 `terraform plan` 不應顯示任何資源需要重建；S3 bucket 內能看到 `.tfstate` 檔案；對同一份 state 同時執行兩個 `terraform apply` 時，DynamoDB lock 會擋下第二個請求。

### 階段 5 — 多環境與生命週期管理（`envs/prod/`）

運用情境：
✅ 維運人員在 prod 誤執行 `terraform destroy`，或改錯程式碼讓 Terraform 判定某個資源要 destroy + create，正式環境的使用者資料表不會真的被砍掉；同一套 `modules/app_service`，dev 環境的資料表依然可以自由重建，不受影響。
✅ 團隊部署新版本的服務程式碼時，不能讓正在處理中的 API 請求因為部署而中斷；新版本出問題時要能立刻切回上一個穩定版本，不用重新 apply 舊程式碼。
✅ 某次部署的程式碼有問題、且對應的 Lambda version 也被誤刪，需要能拿回前幾次部署用的舊版 zip 做緊急還原；但版本記錄不能無限累積佔用儲存空間。
👉 這個階段只在 `envs/prod/teamalpha/` 示範一次，不是把兩個團隊都搬去 prod——重點是驗證生命週期管理機制本身，不是重複勞動複製資料夾。

`envs/prod/teamalpha` 沿用 `envs/dev/teamalpha` 的呼叫方式，改用獨立的 backend key，與 `dev` 完全隔離。這個階段聚焦在 Terraform「建立之後」的行為：

- **`prevent_destroy` 不能吃變數，用 `count` 二選一個資源解決**：`lifecycle` 的 meta-argument（`prevent_destroy`、`create_before_destroy`）跟 `backend` block 一樣，只能寫死字面值，不能引用 `var`/`local`。`modules/app_service` 是 dev/prod 所有團隊共用的同一份模組，不能直接在 `aws_dynamodb_table` 上寫死 `prevent_destroy = true`（會連 dev 也一起鎖住）。做法是用 `count = var.environment == "prod" ? 1 : 0` 讓同一張表依環境對應到兩份定義中的其中一份，只有 prod 那份帶 `prevent_destroy`——這也是「用 `count` 做條件式資源」這個通用技巧的具體案例。
- **Lambda 版本化 + `aws_lambda_alias`**：`aws_lambda_function` 開 `publish = true`，每次 apply 會產生一個不可變的新 published version；`aws_lambda_alias`（例如 `live`）是可以隨時切換指向哪個 version 的指標，API Gateway 打向 alias、不是直接打向 `$LATEST`——出事只要切換 alias 指向的 version，不用重新部署，這正是「Terraform 沒有內建垃圾回收」的具體例子：舊 version 會持續累積，Terraform 不會自動清理。
- **`lambda_artifacts` bucket 補上 versioning + lifecycle rule**：開 `aws_s3_bucket_versioning` 讓每次部署都保留舊版 zip，`aws_s3_bucket_lifecycle_configuration` 只保留 7 天內的版本紀錄，超過自動清除——這是 AWS 原生層級的資源回收機制，跟 Terraform 的 `lifecycle` meta-argument 是完全不同的東西，只是剛好同名。
- `create_before_destroy = true` 已經在階段 3 修 API Gateway deployment bug 時用過（[modules/app_service/main.tf](modules/app_service/main.tf) 的 `aws_api_gateway_deployment`），這裡不重複示範。
- `ignore_changes` 目前這個平台沒有一個「會被平台外機制修改」的自然欄位可以拿來示範，先不勉強套用，等真的遇到再補。

**核心觀念**：State 是 Terraform 唯一的「誰該存在」真相來源，不在 state 裡卻真實存在雲端的孤兒資源，Terraform 不會主動發現或清除，這也是業界會搭配 `driftctl`／`cloud-nuke` 之類工具做稽核的原因。

### 階段 6 — CI/CD 與安全掃描（`.github/workflows/`）

運用情境：
✅ 開發團隊提交 PR 時，自動跑格式檢查、語法驗證、安全掃描（避免 IAM 給過大權限、S3 bucket 忘記關 public access 這類問題被合併進主幹）。
✅ PR 開啟時自動部署一份暫時環境，並對 API 端點跑真實呼叫驗證服務正常。
👉 PR 關閉時自動觸發 `destroy`，暫時環境不會變成沒人管、一直佔用資源的孤兒環境（對應到真實 AWS 上就是一直計費的問題）。

`terraform-ci.yml` 在 PR 觸發時執行 `fmt -check`／`validate`／`tflint`／`checkov`／`plan`；`.pre-commit-config.yaml` 讓同樣的檢查在 commit 前就先攔截。`checkov` 掃描的重點之一就是抓出 hardcode 憑證、未加密的儲存資源、開放給所有人存取的 IAM policy 這類敏感資訊風險，屬於前面「安全與敏感資訊處理原則」在 CI 層級的落地。因為這個平台部署的服務是真的能執行的，CI 額外加入一個 smoke test：`apply` 到暫時環境後直接 `curl` API Gateway 端點驗證回應內容；並在 PR 關閉時觸發對應的 `terraform destroy`（`on: pull_request: types: [closed]`），實踐「用完即丟」的 ephemeral environment 模式——這是銷毀/回收機制在 CI/CD 層級的落地。連向 LocalStack 用的假憑證直接寫在 workflow 環境變數即可；若之後接上真實雲端，這裡要換成 OIDC federation，而不是把長效 access key 存成 GitHub repo secret。

---

完成以上六個階段後，這個 repo 具備完整結構、remote state、多環境隔離、CI/CD、安全掃描，以及一個真正可以部署並存取的服務，涵蓋了軟體工程師職缺所需的核心 Terraform 實踐。
