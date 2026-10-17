# 虛擬驅動自建計畫

本計畫涵蓋虛擬滑鼠相容實作，以及 Zako VDD 官方原始碼試編。兩個驅動維持獨立；後續可由同一個 Sunshine 安裝包管理。試編成功不代表已通過安裝、串流或遊戲相容性測試。

## 邊界與基線

- 現用 Mouse：`AlkaidLab/zako-vmouse-release` v1.3.2。已安裝 DLL 的 SHA-256 是 `D85AFE625E100E1D702737E153AD995A8CCE21D5F264170D13781FB392E98CE4`。目前未找到公開驅動原始碼；反組結果是行為線索，不能視為完整規格或零風險證明。
- 現用 VDD：v0.17.5，來源 commit `88d117431549bcba22fea27ded3d4804c79b51fb`。
- 官方目前 VDD：v0.18.0，來源 commit `22b15167bec5b9ec9ae76e75cbc697704965ab08`，MIT 授權。首次試編固定此提交，並不更新 Sunshine 現有驅動版本。
- 原型不自動安裝、匯入憑證、變更 Secure Boot／測試簽署設定或替換現用驅動。需要實機安裝的階段另行安排。
- 不合併 Mouse 與 VDD 的裝置架構，不擴充鍵盤、檔案傳輸或聯網能力。

## Mouse：先完成相容性規格，再實作

1. **建立行為對照。** 交叉核對 `src/platform/windows/virtual_mouse.cpp`、`input.cpp`、原版 HID 描述與反組的所有請求分支。列出每個欄位、回傳值、長度限制、佇列和生命週期；尚未確認的行為獨立標記。
2. **釐清已知差異。** Sunshine 傳送 8-byte report：ID、按鍵、X/Y 各兩 bytes、垂直／水平滾輪。現用驅動描述只有五鍵、相對 X/Y 與垂直滾輪；水平滾輪的實際效果、7-byte 相容路徑與滿佇列合併行為必須先對照原版確認，不能默認支援或默默省略。
3. **建立自己的原始碼與建置。** 以 Microsoft `Windows-driver-samples/hid/vhidmini2` 的 UMDF 範例為起點，固定來源 commit、保留授權。依已確認的介面獨立撰寫滑鼠功能；先決定自己的裝置識別、並存／切換方式，避免錯開原版裝置。CI 記錄來源、工具鏈、產物摘要，簽署與安裝另列階段。
4. **比較原版與原型。** 相同輸入序列比較 HID 輸出、事件順序、按鍵狀態及錯誤回應。固定案例包括五鍵、拖曳、連續／大幅位移、正負滾輪、組合操作、非法長度／ID、佇列滿載。非法資料先在離線測試層驗證，不直接對現用驅動模糊測試。
5. **實機驗收後才替換。** VoidLink 觸控板、實體滑鼠與實際 Raw Input 遊戲；比較延遲、抖動與漏事件。驗證中斷時放開按鍵、連線恢復、休眠喚醒、裝置重新列舉、SendInput 回退。保留原版回復方式。

完成標準：每個已知原版行為均對應「相同／刻意不同／未驗證」及證據；必需功能不得仍是未驗證。編譯成功只完成建置階段。

## VDD：官方來源試編與後續驗收

1. **未修改來源試編。** 在一次性 Windows 2022 runner，依固定上游 workflow 使用 VS2022、WDK、`ZakoVDD.sln`、Release x64；以 `SignMode=Off` 跳過簽署，保留原專案靜態分析設定。執行上游 EDID profile tests。
2. **保存可追溯證據。** 保留 source commit、workflow commit、runner／VS／WDK 版本、完整編譯 log／binlog、DLL／INF／設定檔與 SHA-256。確認 tracked source 沒有被改寫。這是可追溯試編，尚不承諾逐位元可重現；時間戳、工具鏈和簽章會影響二進位。
3. **相容版本比對。** v0.18.0 成功後，對現用 v0.17.5 做相同試編；比較控制協定、sealed frame／cursor 通道、設定檔與最低 Windows／IddCx 需求。不得把新版能編譯視為可直接取代現版。
4. **先處理發行條件。** 規劃自己的簽署、信任與驅動識別。現有 `verify-driver-certificate.ps1` 固定上游憑證，不能直接放入自建產物。安裝／升級／移除與回復均須有明確方案。
5. **安排獨立實機測試。** 測試建立／移除顯示器、解析度／更新率、SDR／HDR、畫面／游標通道、串流開始／結束、斷線恢復與休眠喚醒；與現版比較，再決定是否進入發行包。

試編入口：[Zako VDD source build check](../.github/workflows/zako-vdd-build-check.yml)。僅產生實驗 artifacts，不建立 Release，也不修改本機。上游工具的 Vulkan／HDR 診斷完整建置不屬於首次 DLL 試編，待版本相容性確認後安排。

### 首次試編結果與下一步

官方相同 commit 的 [v0.18.0 建置](https://github.com/qiin2333/zako-vdd/actions/runs/39015528849) 已通過驅動編譯與 EDID profile tests，證明上游環境能編出來。我們的[獨立試編](https://github.com/Max-FullTek/foundation-sunshine/actions/runs/39061210260) 停在 WDK 準備，尚未執行 MSBuild 編譯或 EDID tests；artifact 目前只有來源證據，沒有新 DLL。

已確認的流程差異：上游使用遞迴搜尋；我們的試編少了遞迴搜尋，找不到實際位於 `Windows Kits/10/Vsix/VS2022/10.0.26100.0/amd64/WDK.vsix` 的套件。下次先修正套件探索，並在 WDK 安裝後重新檢查 build tasks／headers，避免已具備編譯環境卻仍要求 VSIX 安裝。上游成功紀錄中的 VSIX exit code 是 `2001`，因此不能只照目前試編的 exit-code 白名單判定工具鏈不可用；需核對安裝紀錄與實際 tasks。這些差異屬於試編環境流程，尚無 VDD 原始碼編譯失敗證據。

## 本次收工條件與下一階段

- 確認既有 Panel／Core Actions 的實際結果；未完成或失敗就保留狀態與原因，不宣稱已通過。
- 完成上述計畫與首次 VDD 試編，保存成功產物或明確失敗位置。
- 本次不安裝原型，不實作整個 Mouse。下一階段先完成 Mouse 行為對照，再決定原型實作；VDD 依試編結果決定先補環境還是進行 v0.17.5 基線比對。
