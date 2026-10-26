#!/usr/bin/env python3
"""生成 Mac App 的 String Catalog。

用法（需要 opencc：pip install opencc-python-reimplemented）：
    1. 编译一次 Mac App，让编译器导出待翻译字符串
    2. python3 tools/i18n/build_mac_catalog.py

输出：
    macos/LinkToMacOS/Resources/Localizable.xcstrings   界面文字
    macos/LinkToMacOS/Resources/InfoPlist.xcstrings      权限说明、显示名称

源语言是简体中文（代码里的原文就是 key）。缺少翻译的 key 会让脚本报错，避免漏译。
"""
import json
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mac_translations import MANUAL_KEYS, TRANSLATIONS, ZH_HANT_FIXES, ZH_HANT_OVERRIDES  # noqa: E402

try:
    from opencc import OpenCC
except ImportError:
    sys.exit('缺少 opencc：pip install opencc-python-reimplemented')

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
RESOURCES = os.path.join(ROOT, 'macos/LinkToMacOS/Resources')
converter = OpenCC('s2twp')


def zh_hant(key):
    if key in ZH_HANT_OVERRIDES:
        return ZH_HANT_OVERRIDES[key]
    text = converter.convert(key)
    for old, new in ZH_HANT_FIXES:
        text = text.replace(old, new)
    return re.sub(r'“([^”]*)”', r'「\1」', text)  # 繁体中文用「」


def unit(value):
    return {'stringUnit': {'state': 'translated', 'value': value}}


def entry(key, en, ja, manual=False):
    # 简体中文也显式写出（值就是 key），保证每种语言的表都完整，不依赖回落规则
    item = {'localizations': {'zh-Hans': unit(key), 'en': unit(en), 'ja': unit(ja), 'zh-Hant': unit(zh_hant(key))}}
    if manual:
        item['extractionState'] = 'manual'
    return item


def write(path, strings):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    catalog = {'sourceLanguage': 'zh-Hans', 'strings': dict(sorted(strings.items())), 'version': '1.0'}
    with open(path, 'w', encoding='utf-8') as f:
        json.dump(catalog, f, ensure_ascii=False, indent=2)
        f.write('\n')


def main():
    extracted = json.loads(subprocess.check_output([sys.executable, os.path.join(ROOT, 'tools/i18n/mac_keys.py')]))
    if extracted['missing']:
        sys.exit('有中文字符串没有被编译器提取（不会被翻译）：\n' + '\n'.join(f'  {w} | {t}' for w, t in extracted['missing']))
    keys = list(dict.fromkeys(extracted['keys'] + MANUAL_KEYS))
    absent = [k for k in keys if k not in TRANSLATIONS]
    if absent:
        sys.exit('缺少翻译：\n' + '\n'.join(f'  {k!r}' for k in absent))
    unused = [k for k in TRANSLATIONS if k not in keys]  # 扩展用的 key 也会出现在这里，提示即可
    if unused:
        print('提示：翻译表里有这些 key 已不再使用：', unused)

    write(os.path.join(RESOURCES, 'Localizable.xcstrings'),
          {k: entry(k, *TRANSLATIONS[k], manual=k in MANUAL_KEYS) for k in keys})

    # 扩展（共享菜单、桌面小组件）各有自己的字符串表，翻译共用同一张表
    for target in ('AirSendShare', 'LinkWidget', 'LinkMirror'):
        sub = json.loads(subprocess.check_output([sys.executable, os.path.join(ROOT, 'tools/i18n/mac_keys.py'), target]))
        if sub['missing']:
            sys.exit(f'{target} 有中文字符串没有被编译器提取：\n' + '\n'.join(f'  {w} | {t}' for w, t in sub['missing']))
        sub_keys = list(dict.fromkeys(sub['keys']))
        absent = [k for k in sub_keys if k not in TRANSLATIONS]
        if absent:
            sys.exit(f'{target} 缺少翻译：\n' + '\n'.join(f'  {k!r}' for k in absent))
        write(os.path.join(ROOT, 'macos', target, 'Localizable.xcstrings'), {k: entry(k, *TRANSLATIONS[k]) for k in sub_keys})

    # 系统权限说明和显示名称
    plist = {
        'NSLocalNetworkUsageDescription': (
            '用于在局域网内发现并连接你的 Android 手机。',
            'Used to find and connect to your Android phone on the local network.',
            'ローカルネットワーク上の Android スマートフォンを検出して接続するために使用します。'),
        'NSBluetoothAlwaysUsageDescription': (
            '用于通过蓝牙在电脑上接打手机电话。',
            'Used to make and answer phone calls from this Mac over Bluetooth.',
            'Bluetooth 経由でこの Mac からスマートフォンの電話を発着信するために使用します。'),
        'NSMicrophoneUsageDescription': (
            '用于在投屏时把你的声音传给手机，以及在电脑上接打手机电话时采集声音。',
            'Used to send your voice to the phone while mirroring, and when making or answering phone calls on this Mac.',
            '画面ミラーリング中にあなたの声をスマートフォンに送るため、およびこの Mac で通話するときに音声を取得するために使用します。'),
    }
    hant = {
        'NSLocalNetworkUsageDescription': '用於在區域網路內探索並連線你的 Android 手機。',
        'NSBluetoothAlwaysUsageDescription': '用於透過藍牙在 Mac 上撥打和接聽手機電話。',
        'NSMicrophoneUsageDescription': '用於在螢幕鏡像時將你的聲音傳給手機，以及在 Mac 上撥打或接聽手機電話時收錄你的聲音。',
    }
    write(os.path.join(RESOURCES, 'InfoPlist.xcstrings'),
          {k: {'localizations': {'zh-Hans': unit(zh), 'en': unit(en), 'ja': unit(ja), 'zh-Hant': unit(hant[k])}}
           for k, (zh, en, ja) in plist.items()})
    print(f'完成：{len(keys)} 条界面文字 + {len(plist)} 条权限说明；语言 zh-Hans / zh-Hant / en / ja')


if __name__ == '__main__':
    main()
