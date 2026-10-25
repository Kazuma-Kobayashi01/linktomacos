#!/usr/bin/env python3
"""生成 Android 的多语言资源。

用法（需要 opencc：pip install opencc-python-reimplemented）：python3 tools/i18n/android_strings.py

输出：
    android/app/src/main/res/values/strings.xml          英文（默认）
    android/app/src/main/res/values-zh-rCN/strings.xml   简体中文
    android/app/src/main/res/values-zh-rTW/strings.xml   繁体中文（台湾）
    android/app/src/main/res/values-zh-rHK/strings.xml   繁体中文（香港，内容同台湾）
    android/app/src/main/res/values-ja/strings.xml       日文
    android/app/src/main/res/xml/locales_config.xml      系统“按应用设置语言”用

每条是 (简体中文, 英文, 日文)。繁体由 OpenCC 转换，再用 FIXES / OVERRIDES 修正用词。
"""
import os
import re
import sys
from xml.sax.saxutils import escape

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mac_translations import ZH_HANT_FIXES  # noqa: E402

try:
    from opencc import OpenCC
except ImportError:
    sys.exit('缺少 opencc：pip install opencc-python-reimplemented')

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
RES = os.path.join(ROOT, 'android/app/src/main/res')

STRINGS = {
    # --- 首页：配对 ---
    'pair_scan': ('扫码配对 Mac', 'Scan to Pair Mac', 'スキャンして Mac とペアリング'),
    'pair_paste': ('粘贴配对链接', 'Paste Pairing Link', 'ペアリングリンクを貼り付け'),
    'paired_with': ('已配对：%1$s', 'Paired with: %1$s', 'ペアリング済み：%1$s'),
    're_pair': ('重新配对', 'Pair Again', '再ペアリング'),
    'unpair': ('取消配对', 'Unpair', 'ペアリング解除'),
    'link_invalid': ('链接无效', 'Invalid link', 'リンクが無効です'),
    'pair': ('配对', 'Pair', 'ペアリング'),
    'cancel': ('取消', 'Cancel', 'キャンセル'),
    'back': ('返回', 'Back', '戻る'),

    # --- 首页：连接状态 ---
    'state_not_paired_title': ('未配对', 'Not Paired', '未ペアリング'),
    'state_not_paired_detail': (
        '在 Mac 菜单栏点击“配对新手机…”，然后扫描二维码',
        'In the Mac menu bar, choose “Pair New Phone…”, then scan the QR code',
        'Mac のメニューバーで「新しいスマートフォンをペアリング…」を選び、QR コードをスキャンしてください'),
    'state_searching_title': ('正在连接', 'Connecting', '接続中'),
    'state_connected_title': ('已连接', 'Connected', '接続済み'),
    'state_waiting_title': ('未连接', 'Not Connected', '未接続'),
    'state_waiting_detail': ('%1$s，%2$d 秒后重试', '%1$s. Retrying in %2$d s', '%1$s。%2$d 秒後に再試行します'),
    'state_rejected_title': ('被拒绝', 'Rejected', '拒否されました'),
    'state_rejected_detail': (
        '%1$s：%2$s。请重新扫码配对',
        '%1$s: %2$s. Please scan the QR code to pair again',
        '%1$s：%2$s。もう一度 QR コードをスキャンしてペアリングしてください'),

    # --- 首页：通知转发 ---
    'notif_title': ('通知转发', 'Notification Forwarding', '通知の転送'),
    'notif_need_access': (
        '需要开启“通知使用权”，才能把手机通知转发到 Mac',
        'Turn on “Notification access” to forward phone notifications to your Mac',
        'スマートフォンの通知を Mac に転送するには、「通知へのアクセス」をオンにしてください'),
    'notif_none_selected': (
        '还没有选择任何应用，请先选择要转发通知的应用',
        'No apps selected yet. Choose which apps’ notifications to forward',
        'アプリが選択されていません。通知を転送するアプリを選んでください'),
    'go_enable': ('去开启', 'Turn On', 'オンにする'),
    'choose_apps': ('选择应用', 'Choose Apps', 'アプリを選択'),

    # --- 首页：免打扰 ---
    'dnd_title': ('免打扰', 'Do Not Disturb', 'おやすみモード'),
    'dnd_auto': ('连接 Mac 时自动开启免打扰', 'Turn on Do Not Disturb when connected to Mac', 'Mac に接続中は自動でおやすみモードをオン'),
    'dnd_auto_sub': (
        '断开、Mac 退出或睡眠时自动关闭',
        'Turns off when disconnected, or when the Mac quits or sleeps',
        '切断時、Mac の終了・スリープ時に自動でオフ'),
    'dnd_ring': ('免打扰期间来电仍然响铃', 'Still ring for incoming calls during Do Not Disturb', 'おやすみモード中も着信音を鳴らす'),
    'dnd_need_policy': (
        '需要授予“勿扰权限”才能自动开关免打扰',
        'Grant “Do Not Disturb access” so the app can turn it on and off automatically',
        '自動でオン/オフするには「おやすみモードへのアクセス」の許可が必要です'),
    'go_grant': ('去授权', 'Grant', '許可する'),
    'dnd_error': ('免打扰出错：%1$s', 'Do Not Disturb error: %1$s', 'おやすみモードのエラー：%1$s'),
    'dnd_active': ('免打扰已由本应用开启', 'Do Not Disturb has been turned on by this app', 'おやすみモードはこのアプリによってオンになっています'),
    'dnd_inactive': (
        '当前未开启（连接 Mac 后自动开启）',
        'Currently off (turns on when connected to Mac)',
        '現在オフ（Mac に接続すると自動でオンになります）'),
    'dnd_no_access': (
        '未授予“勿扰权限”，无法自动开启免打扰',
        '“Do Not Disturb access” isn’t granted, so it can’t be turned on automatically',
        '「おやすみモードへのアクセス」が許可されていないため、自動でオンにできません'),
    'dnd_rule_name': ('已连接 Mac', 'Connected to Mac', 'Mac に接続中'),

    # --- 首页：相册与文件 ---
    'files_title': ('相册与文件', 'Photos & Files', '写真とファイル'),
    'files_desc': (
        '在 Mac 上浏览手机的相册和文件，需要下面两项授权',
        'To browse this phone’s photos and files on your Mac, grant these two permissions',
        'Mac でこのスマートフォンの写真とファイルを見るには、次の2つの許可が必要です'),
    'files_media': ('相册读取（需选“允许全部”）', 'Photo access (choose “Allow all”)', '写真へのアクセス（「すべて許可」を選択）'),
    'files_all': ('所有文件访问', 'All files access', 'すべてのファイルへのアクセス'),
    'granted': ('已授权', 'Granted', '許可済み'),
    'not_granted': ('未授权', 'Not granted', '未許可'),

    # --- 首页：保持连接 ---
    'keepalive_title': ('保持连接', 'Stay Connected', '接続を維持'),
    'keepalive_steps': (
        '1. 关闭电池优化（应用电池设为“不受限制”）\\n2. 设置 → 电池 → 后台使用限制 → 将本应用加入“从不休眠的应用”\\n3. 关闭“自动拦截器”',
        '1. Turn off battery optimization (set this app’s battery usage to “Unrestricted”)\\n2. Settings → Battery → Background usage limits → add this app to “Never sleeping apps”\\n3. Turn off “Auto Blocker”',
        '1. バッテリー最適化をオフにする（このアプリのバッテリー使用を「制限なし」に）\\n2. 設定 → バッテリー → バックグラウンド使用制限 → このアプリを「スリープしないアプリ」に追加\\n3. 「オートブロッカー」をオフにする'),
    'battery_opt_off': ('电池优化已关闭', 'Battery optimization is off', 'バッテリー最適化はオフです'),
    'battery_opt_turn_off': ('关闭电池优化', 'Turn Off Battery Optimization', 'バッテリー最適化をオフにする'),
    'app_info': ('应用信息', 'App Info', 'アプリ情報'),

    # --- 选择应用 ---
    'picker_title': ('选择要转发的应用', 'Choose Apps to Forward', '転送するアプリを選択'),
    'picker_hint': (
        '只有勾选的应用的通知会转发到 Mac（已选 %1$d 个）',
        'Only notifications from checked apps are forwarded to your Mac (selected: %1$d)',
        'チェックしたアプリの通知だけが Mac に転送されます（選択中：%1$d）'),
    'picker_search': ('搜索应用', 'Search apps', 'アプリを検索'),

    # --- 扫码 ---
    'need_camera': ('需要相机权限才能扫码', 'Camera permission is needed to scan the code', 'コードをスキャンするにはカメラの許可が必要です'),
    'not_pairing_code': ('不是 LinkToMacOS 的配对码', 'This isn’t a LinkToMacOS pairing code', 'LinkToMacOS のペアリングコードではありません'),
    'scan_hint': (
        '对准 Mac 上的配对二维码',
        'Point the camera at the pairing QR code on your Mac',
        'Mac に表示されたペアリング QR コードにカメラを向けてください'),

    # --- 前台服务通知 ---
    'channel_name': ('连接状态', 'Connection status', '接続状態'),
    'channel_desc': ('与 Mac 的连接状态（常驻）', 'Ongoing status of the connection to your Mac', 'Mac との接続状態（常時表示）'),
    'svc_starting': ('正在启动…', 'Starting…', '起動中…'),
    'svc_not_found': ('未找到 Mac', 'Mac not found', 'Mac が見つかりません'),
    'svc_cannot_connect': ('无法连接 Mac', 'Can’t connect to Mac', 'Mac に接続できません'),
    'svc_handshake_failed': ('握手失败', 'Handshake failed', 'ハンドシェイクに失敗しました'),
    'svc_mac_refused': ('Mac 拒绝连接', 'Mac refused the connection', 'Mac が接続を拒否しました'),
    'svc_conn_interrupted': ('连接中断', 'Connection interrupted', '接続が中断されました'),
    'svc_heartbeat_timeout': ('心跳超时', 'Heartbeat timed out', 'ハートビートがタイムアウトしました'),
    'svc_mac_left': ('Mac 已断开（%1$s）', 'Mac disconnected (%1$s)', 'Mac が切断しました（%1$s）'),
    'notif_not_paired': ('尚未配对 Mac', 'No Mac paired', 'Mac が未ペアリングです'),
    'notif_connecting': ('正在连接 %1$s…', 'Connecting to %1$s…', '%1$s に接続中…'),
    'notif_connected': ('已连接 %1$s', 'Connected to %1$s', '%1$s に接続済み'),
    'notif_rejected': ('%1$s 拒绝连接：%2$s', '%1$s refused the connection: %2$s', '%1$s が接続を拒否しました：%2$s'),

    # --- 首页：投屏增强服务 ---
    'enhanced_title': ('投屏增强服务', 'Mirroring Service', 'ミラーリングサービス'),
    'enhanced_running': (
        '已运行：投屏不需要每次授权，并支持真实触摸',
        'Running: mirroring needs no per-session approval and supports real touch',
        '動作中：毎回の許可なしでミラーリングでき、実際のタッチ操作に対応します'),
    'enhanced_stopped': (
        '未运行。在 Mac 的“投屏”页面用 USB 数据线启动一次，之后拔掉也一直有效，直到手机重启',
        'Not running. Start it once from the Mac’s Screen Mirroring page over USB; it keeps running after you unplug until the phone restarts',
        '停止中。Mac の「ミラーリング」ページから USB 接続で一度起動してください。ケーブルを外しても、スマートフォンを再起動するまで動作し続けます'),

    # --- 发给 Mac 的错误提示 ---
    'err_enhanced_not_ready': (
        '增强服务没有运行，请在 Mac 上通过 USB 启动',
        'The enhanced service isn’t running. Start it from your Mac over USB',
        '拡張サービスが動作していません。USB 経由で Mac から起動してください'),
    'err_launch_failed': ('无法打开应用：%1$s', 'Couldn’t open the app: %1$s', 'アプリを開けません：%1$s'),
    'err_mirror_start_failed': ('无法开始投屏：%1$s', 'Couldn’t start mirroring: %1$s', 'ミラーリングを開始できません：%1$s'),
    'err_unsupported_request': ('不支持的请求：%1$s', 'Unsupported request: %1$s', 'サポートされていないリクエスト：%1$s'),
    'err_no_media_access': ('手机未授予相册读取权限', 'The phone hasn’t granted photo access', 'スマートフォンで写真へのアクセスが許可されていません'),
    'err_cannot_read_photos': ('无法读取相册', 'Can’t read photos', '写真を読み込めません'),
    'err_other_album': ('其他', 'Other', 'その他'),
    'err_missing_id': ('缺少 id', 'Missing id', 'id がありません'),
    'err_missing_path': ('缺少 path', 'Missing path', 'path がありません'),
    'err_no_all_files': ('手机未授予“所有文件访问权限”', 'The phone hasn’t granted “All files access”', 'スマートフォンで「すべてのファイルへのアクセス」が許可されていません'),
    'err_invalid_path': ('路径无效', 'Invalid path', 'パスが無効です'),
    'err_cannot_read_folder': ('无法读取该文件夹', 'Can’t read this folder', 'このフォルダを読み込めません'),
    'err_file_gone': ('文件已不存在', 'The file no longer exists', 'ファイルは既に存在しません'),
    'err_cannot_open_file': ('无法打开文件', 'Can’t open the file', 'ファイルを開けません'),
    'err_not_a_file': ('不是文件', 'Not a file', 'ファイルではありません'),
    'err_unknown_source': ('未知的下载来源', 'Unknown download source', '不明なダウンロード元です'),
    'err_cancelled': ('已取消', 'Cancelled', 'キャンセルしました'),
    'err_read_failed': ('读取失败', 'Read failed', '読み込みに失敗しました'),
}

PLURALS = {
    'apps_selected': {
        'zh': '已选择 %1$d 个应用，它们的新通知会显示在 Mac 上',
        'en': {'one': '%1$d app selected. Its new notifications will appear on your Mac',
               'other': '%1$d apps selected. Their new notifications will appear on your Mac'},
        'ja': '%1$d 個のアプリを選択中。新しい通知が Mac に表示されます',
    },
}

# 台湾 / 三星界面用语的修正（在通用修正之后执行；用正则是为了避免重复替换）
ANDROID_FIXES = [
    (r'免打擾', '請勿打擾'),
    (r'勿擾權限', '「請勿打擾」權限'),
    (r'後臺|後台', '背景'),
    (r'電池優化', '電池最佳化'),
    (r'自動攔截器', '自動封鎖程式'),
    (r'從不休眠的應用', '永不休眠的應用程式'),
    (r'應用(?!程式)', '應用程式'),
    (r'相簿讀取', '照片讀取'),
    (r'二維碼', 'QR Code'),
    (r'通知使用權', '通知存取權'),
]

ZH_HANT_OVERRIDES = {
    'pair_scan': '掃描 QR Code 配對 Mac',
    'state_not_paired_detail': '在 Mac 選單列點選「配對新手機…」，然後掃描 QR Code',
    'scan_hint': '將相機對準 Mac 上的配對 QR Code',
    'state_rejected_detail': '%1$s：%2$s。請重新掃描 QR Code 配對',
    'not_pairing_code': '這不是 LinkToMacOS 的配對碼',
    'need_camera': '需要相機權限才能掃描',
    'files_media': '相片讀取（請選「全部允許」）',
    'dnd_inactive': '目前未開啟（連線 Mac 後自動開啟）',
    'err_cannot_read_photos': '無法讀取相片',
    'err_no_media_access': '手機未授予相片讀取權限',
    'dnd_need_policy': '需要授予「請勿打擾」權限，才能自動開關請勿打擾',
    'dnd_no_access': '未授予「請勿打擾」權限，無法自動開啟請勿打擾',
    'dnd_ring': '請勿打擾期間來電仍然響鈴',
    'enhanced_stopped': '未執行。請在 Mac 的「螢幕鏡像」頁面透過 USB 線啟動一次，之後拔掉線也會持續有效，直到手機重新開機',
    'enhanced_running': '執行中：鏡像不必每次授權，並支援真實觸控',
    'back': '返回',
    'files_title': '相片與檔案',
    'files_desc': '在 Mac 上瀏覽手機的相片和檔案，需要下面兩項授權',
    'dnd_error': '請勿打擾發生錯誤：%1$s',
    'go_enable': '前往開啟',
    'go_grant': '前往授權',
}

converter = OpenCC('s2twp')


def zh_hant(key, text):
    if key in ZH_HANT_OVERRIDES:
        return ZH_HANT_OVERRIDES[key]
    out = converter.convert(text)
    for old, new in ZH_HANT_FIXES:
        out = out.replace(old, new)
    for pattern, new in ANDROID_FIXES:
        out = re.sub(pattern, new, out)
    return re.sub(r'“([^”]*)”', r'「\1」', out)


def xml_text(value):
    # \n 在 strings.xml 里是换行转义；撇号和引号需要转义
    value = escape(value).replace("'", "\\'").replace('"', '\\"')
    return value


def write(folder, entries, plurals):
    os.makedirs(os.path.join(RES, folder), exist_ok=True)
    lines = ['<?xml version="1.0" encoding="utf-8"?>', '<!-- 由 tools/i18n/android_strings.py 生成，请改脚本而不是这个文件 -->', '<resources>']
    for key, value in entries.items():
        lines.append(f'    <string name="{key}">{xml_text(value)}</string>')
    for key, items in plurals.items():
        lines.append(f'    <plurals name="{key}">')
        for quantity, value in items.items():
            lines.append(f'        <item quantity="{quantity}">{xml_text(value)}</item>')
        lines.append('    </plurals>')
    lines.append('</resources>')
    with open(os.path.join(RES, folder, 'strings.xml'), 'w', encoding='utf-8') as f:
        f.write('\n'.join(lines) + '\n')


def placeholders(text):
    return sorted(re.findall(r'%\d\$[sd]', text))


def check_placeholders():
    problems = []
    for key, (zh, en, ja) in STRINGS.items():
        for lang, text in (('en', en), ('ja', ja)):
            if placeholders(text) != placeholders(zh):
                problems.append(f'{key} [{lang}]: {placeholders(text)} != {placeholders(zh)}')
        hant = zh_hant(key, zh)
        if placeholders(hant) != placeholders(zh):
            problems.append(f'{key} [zh-TW]: {placeholders(hant)} != {placeholders(zh)}')
    for key, items in PLURALS.items():
        for lang, value in items.items():
            for text in ([value] if isinstance(value, str) else value.values()):
                if placeholders(text) != placeholders(items['zh']):
                    problems.append(f'{key} [{lang}]: 占位符不一致')
    if problems:
        sys.exit('占位符不一致：\n  ' + '\n  '.join(problems))


def main():
    check_placeholders()
    zh = {k: v[0] for k, v in STRINGS.items()}
    en = {k: v[1] for k, v in STRINGS.items()}
    ja = {k: v[2] for k, v in STRINGS.items()}
    hant = {k: zh_hant(k, v) for k, v in zh.items()}
    plural_of = lambda lang: {k: ({'other': v[lang]} if isinstance(v[lang], str) else v[lang]) for k, v in PLURALS.items()}  # noqa: E731
    plural_hant = {k: {'other': zh_hant(k, v['zh'])} for k, v in PLURALS.items()}

    write('values', en, plural_of('en'))
    write('values-zh-rCN', zh, plural_of('zh'))
    write('values-zh-rTW', hant, plural_hant)
    write('values-zh-rHK', hant, plural_hant)
    write('values-ja', ja, plural_of('ja'))

    os.makedirs(os.path.join(RES, 'xml'), exist_ok=True)
    with open(os.path.join(RES, 'xml/locales_config.xml'), 'w', encoding='utf-8') as f:
        f.write('<?xml version="1.0" encoding="utf-8"?>\n<locale-config xmlns:android="http://schemas.android.com/apk/res/android">\n'
                + ''.join(f'    <locale android:name="{tag}" />\n' for tag in ['en', 'zh-CN', 'zh-TW', 'zh-HK', 'ja'])
                + '</locale-config>\n')
    print(f'完成：{len(STRINGS)} 条文字 + {len(PLURALS)} 条复数；语言 en / zh-CN / zh-TW / zh-HK / ja')


if __name__ == '__main__':
    main()
