import Foundation

/// UI languages: Vietnamese (default) + English, Chinese, Japanese, Korean, Spanish.
enum Lang: String, CaseIterable, Identifiable {
    case vi, en, zh, ja, ko, es
    var id: String { rawValue }
    var name: String {
        switch self { case .vi: return "Tiếng Việt"; case .en: return "English"; case .zh: return "中文"; case .ja: return "日本語"; case .ko: return "한국어"; case .es: return "Español" }
    }
}

var currentLang: Lang { Lang(rawValue: UserDefaults.standard.string(forKey: "lang") ?? "vi") ?? .vi }

/// Translate a key into the current language; order of each row: vi, en, zh, ja, ko, es.
func T(_ key: String) -> String {
    guard let row = strings[key] else { return key }
    let i = Lang.allCases.firstIndex(of: currentLang) ?? 0
    return i < row.count ? row[i] : row[0]
}

private let strings: [String: [String]] = [
    "reset_in":     ["reset sau", "resets in", "重置倒计时", "リセットまで", "초기화까지", "se reinicia en"],
    "reset_done":   ["đã reset", "reset", "已重置", "リセット済み", "초기화됨", "reiniciado"],
    "left":         ["còn", "left", "剩余", "残り", "남음", "queda"],
    "in_use":       ["Đang dùng", "In use", "使用中", "使用中", "사용 중", "En uso"],
    "limit_hit":    ["Đã chạm limit", "Limit reached", "已达上限", "上限に達しました", "한도 도달", "Límite alcanzado"],
    "blocked_until":["hết lượt tới", "blocked until", "暂停至", "利用不可:", "차단 해제:", "bloqueado hasta"],
    "set_default":  ["Bấm để đặt làm model mặc định", "Click to set as default model", "点击设为默认模型", "クリックで既定モデルに設定", "클릭하여 기본 모델로 설정", "Clic para usar como modelo predeterminado"],
    "models":       ["Models", "Models", "模型", "モデル", "모델", "Modelos"],
    "models_hint":  ["bấm để switch", "click to switch", "点击切换", "クリックで切替", "클릭하여 전환", "clic para cambiar"],
    "settings":     ["Cài đặt", "Settings", "设置", "設定", "설정", "Ajustes"],
    "back":         ["Quay lại", "Back", "返回", "戻る", "뒤로", "Volver"],
    "language":     ["Ngôn ngữ", "Language", "语言", "言語", "언어", "Idioma"],
    "refresh_every":["Tự refresh mỗi", "Auto refresh every", "自动刷新间隔", "自動更新の間隔", "자동 새로고침 간격", "Actualizar cada"],
    "menubar_show": ["Menu bar hiển thị", "Menu bar shows", "菜单栏显示", "メニューバー表示", "메뉴 막대 표시", "Barra de menús"],
    "all3":         ["Cả 3", "All 3", "全部", "すべて", "전체", "Los 3"],
    "accounts":     ["Tài khoản", "Accounts", "账户", "アカウント", "계정", "Cuentas"],
    "add_account":  ["Thêm tài khoản", "Add account", "添加账户", "アカウントを追加", "계정 추가", "Añadir cuenta"],
    "default_acc":  ["mặc định (máy này)", "default (this Mac)", "默认（本机）", "既定（このMac）", "기본 (이 Mac)", "predeterminada (este Mac)"],
    "remove":       ["Xoá", "Remove", "删除", "削除", "삭제", "Quitar"],
    "name_hint":    ["Tên (vd: Work)", "Name (e.g. Work)", "名称（如 Work）", "名前（例: Work）", "이름 (예: Work)", "Nombre (p. ej. Work)"],
    "login_hint":   ["Mở Terminal để login. Xong bấm ↻.", "Opens Terminal to log in. Then press ↻.", "将打开终端登录，完成后点 ↻。", "ターミナルでログイン後、↻ を押してください。", "터미널에서 로그인 후 ↻ 를 누르세요.", "Abre Terminal para iniciar sesión. Luego pulsa ↻."],
    "login":        ["Login", "Log in", "登录", "ログイン", "로그인", "Entrar"],
    "show_email":   ["Hiện email", "Show emails", "显示邮箱", "メールを表示", "이메일 표시", "Mostrar correos"],
    "tap_reveal":   ["bấm để hiện email", "click to show email", "点击显示邮箱", "クリックでメール表示", "클릭하여 이메일 표시", "clic para ver el correo"],
    "coffee":       ["Mời mình ly cà phê", "Buy me a coffee", "请我喝杯咖啡", "コーヒーをおごる", "커피 한 잔 사주기", "Invítame a un café"],
    "quit":         ["Thoát", "Quit", "退出", "終了", "종료", "Salir"],
    "sec":          ["giây", "sec", "秒", "秒", "초", "s"],
    "min":          ["phút", "min", "分钟", "分", "분", "min"],
    "not_logged_claude": ["Chưa login. Chạy `claude login`.", "Not logged in. Run `claude login`.", "未登录。请运行 `claude login`。", "未ログイン。`claude login` を実行してください。", "로그인되지 않음. `claude login` 실행.", "Sin sesión. Ejecuta `claude login`."],
    "not_logged_codex":  ["Chưa login. Chạy `codex login`.", "Not logged in. Run `codex login`.", "未登录。请运行 `codex login`。", "未ログイン。`codex login` を実行してください。", "로그인되지 않음. `codex login` 실행.", "Sin sesión. Ejecuta `codex login`."],
    "not_logged_agy":    ["Chưa login. Chạy `agy` để đăng nhập.", "Not logged in. Run `agy` to log in.", "未登录。请运行 `agy` 登录。", "未ログイン。`agy` を実行してログインしてください。", "로그인되지 않음. `agy` 를 실행해 로그인하세요.", "Sin sesión. Ejecuta `agy` para entrar."],
    "expired_claude":    ["Token hết hạn — mở `claude` 1 lần để refresh.", "Token expired — open `claude` once to refresh.", "令牌已过期——打开一次 `claude` 刷新。", "トークン期限切れ — `claude` を一度開いて更新してください。", "토큰 만료 — `claude` 를 한 번 실행해 갱신하세요.", "Token caducado: abre `claude` una vez para renovarlo."],
    "expired_codex":     ["Token hết hạn — chạy `codex` 1 lần để refresh.", "Token expired — run `codex` once to refresh.", "令牌已过期——运行一次 `codex` 刷新。", "トークン期限切れ — `codex` を一度実行して更新してください。", "토큰 만료 — `codex` 를 한 번 실행해 갱신하세요.", "Token caducado: ejecuta `codex` una vez para renovarlo."],
    "extra_on":     ["Extra usage bật", "Extra usage on", "额外用量已开启", "追加使用量: オン", "추가 사용량 켜짐", "Uso extra activado"],
    "extra_off":    ["Extra usage tắt", "Extra usage off", "额外用量已关闭", "追加使用量: オフ", "추가 사용량 꺼짐", "Uso extra desactivado"],
    "resets_left":  ["lượt reset còn lại", "resets remaining", "次重置可用", "回のリセットが残り", "회 초기화 남음", "reinicios disponibles"],
    "agy_unreadable":["Không đọc được `agy -p /usage`.", "Could not read `agy -p /usage`.", "无法读取 `agy -p /usage`。", "`agy -p /usage` を読み取れません。", "`agy -p /usage` 를 읽을 수 없음.", "No se pudo leer `agy -p /usage`."],
]
