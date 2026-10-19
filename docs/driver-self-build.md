# 自建驅動的包版與獨立更新

Foundation Sunshine Lite 僅支援 Windows 11 x64。VDD 與虛擬滑鼠維持獨立專案；Lite 安裝包內附固定版本，也可使用獨立驅動 ZIP 安裝、升級與移除，不必重編主程式。

## 來源與固定版本

- VDD：`Max-FullTek/zako-vdd`，來源 `9f6b00b20cf7c8584ee06e09a362514773edf70f`，驅動版本 `100.0.18.0`。
- 滑鼠：`Max-FullTek/foundation-virtual-mouse`，來源 `ceeff46c393854c5855e380c77684a1bb163b63f`，來源版本 `0.4.0.0`，簽署 INF 的 DriverVer 為 `4.32.8.6`（升降級依此判斷），搭配權限 Extension `0.1.0.0`。兩份 INF／CAT 必須一起發佈，不能只替換 DLL。
- 簽署產物保存於 `src_assets/windows/drivers/vdd/`、`vmouse/`。每包的 `package.json` 記錄來源、CI、版本及逐檔 SHA-256；保留 MIT／MS-PL 授權。簽署後的 INF 與 DLL 不得直接修改或改名。
- `verify-driver-certificate.ps1` 固定公有憑證 SHA-256，驗證檔案摘要、憑證有效期及每份 catalog 的密碼學簽章。Windows 匯入驅動時再執行 catalog 成員驗證。不下載上游舊滑鼠、舊 VDD 或 Windows 10 備援。

## 發佈與更新

更新驅動時，先在各自專案建置及簽署，再將完整產物與來源紀錄更新到對應目錄。重新簽署會改變 DLL／CAT 雜湊，必須更新 manifest；更換簽署憑證則必須獨立核對並更新驗證器的 pin。

執行 `Package independent Foundation drivers` workflow，可選 VDD、滑鼠或兩者。它驗證並包裝現有簽署產物與固定雜湊的 nefcon，另從固定來源編譯 Vulkan HDR 使用者模式工具；不編譯 Lite／GUI，也不安裝驅動。只更新驅動產物的 master 提交會執行此 workflow，跳過完整 Lite workflow。共用安裝腳本、核心或 GUI 改動仍須正常建置。

新增 workflow 必須先合併到預設分支，GitHub 才能接受手動 dispatch；功能分支階段可直接使用下列本機入口。

本機入口：

```powershell
./scripts/package-drivers.ps1 -Component all -OutputDirectory G:/output/foundation-drivers
```

輸出目錄必須尚不存在。各 ZIP 解壓後，以管理員執行 `Install.cmd` 或 `Uninstall.cmd`。安裝會先停止 Sunshine 服務；只在驗證成功後恢復原本運行的服務。VDD 更新沿用已安裝 Lite 的設定目錄，不覆蓋既有 XML。較舊 Lite 的內附驅動不應降級健康的較新驅動。Windows 要求重啟時回傳 3010，不自動重新啟動電腦。

Lite 本身的安裝包仍然內附該次提交固定的驅動版本。只有要更新 Lite 安裝包內附的版本時，才需要重新包裝 Lite；使用者可先單獨更新驅動。現階段提供獨立手動更新，沒有背景自動下載驅動或自動信任新憑證。

## 簽署與安裝邊界

現用憑證指紋為 `78983DA4728FBB6B57779A60F6B1A2F071C84F07`，有效至 2027-01-18。這是本機簽署憑證，並非 Microsoft WHQL／attestation。安裝介面會明示加入信任存放區；簽章到期或不同憑證會拒絕包裝，不自動信任隨包的新憑證，也不變更 Secure Boot／測試簽署設定。

滑鼠安裝只處理 Foundation 的確切 root／child 識別。先匯入權限 Extension，再建立或更新 root；必須確認 child 的即時 DACL 僅允許 SYSTEM／管理員，才回報成功並清除確切的舊 Zako 滑鼠。更新失敗時保持未驗證完成的 root 停用、保留 DriverStore 套件供修復，不偽裝成功或自動重開服務。VDD 沿用既有精確裝置識別與更新交易復原流程。

現有實機紀錄涵蓋 VDD 基本 HDR／退出後螢幕恢復，以及滑鼠移動、左右鍵、拖曳、雙向捲動與權限限制。此整合沒有執行新安裝、重開機或完整生命週期驗收；套件納入正式包版不代表這些項目已驗證，也不構成無後門／無遙測的證明。

Vulkan HDR 相容元件改由 Lite 的 `third-party/zako-vulkan-hdr/` 固定來源自行編譯，來源版本與原檔 SHA-256 記錄於 `source.json`，沿用 MIT 授權。Core 與 WebUI 預設均關閉，僅使用者明確啟用後才在 HDR VDD 串流期間探測與暫時註冊。既有設定若已明確啟用，會保留該選擇。Lite 安裝器與獨立 VDD ZIP 都會包含橋接 DLL、layer manifest、probe、授權與來源紀錄；獨立更新在成功後同步已安裝 Lite 的工具檔案，複製不會註冊或啟用 Layer。

這次檢查範圍為橋接 DLL、probe、兩者直接使用的 header、建置／註冊整合。未發現網路端點、連線／上傳、遙測 SDK、背景下載或外部指令執行。能力快取僅在本機保存 GPU 名稱／識別、驅動與 Windows 版本、HDR 探測旗標；probe 的登錄操作限使用者 HKCU 的 Vulkan ImplicitLayers，新增指定 manifest，清除相同檔名的舊註冊。不讀取帳密或遊戲內容，也不安裝服務／排程工作。這是限定範圍的原始碼與匯入檢查，不是完整安全稽核或整台電腦無遙測的保證。

本地調整移除了測試用強制啟用／跨螢幕／任意快取路徑環境變數，probe 只從 Windows System32 載入 Vulkan loader，並保留能力驗證失敗時不啟用橋接的行為。Layer 啟用期間可能被同使用者其他 Vulkan 程式載入，但只對識別到的 HDR VDD surface 補格式；不能宣稱每款遊戲或反作弊均相容。此版本仍沿用上游的精簡 Vulkan ABI 宣告，屬實驗性元件；尚未完成實際 Vulkan 遊戲 HDR 驗證，沒有以探測或編譯成功替代此驗收。
