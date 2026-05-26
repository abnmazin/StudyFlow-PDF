#!/usr/bin/env python3
"""
Debug script: Fetches Instagram homepage with a session ID and dumps token extraction results.
Run: python debug_extract.py <your_session_id>
"""
import requests
import re
import sys
import json
import uuid
import os

os.environ['PYTHONIOENCODING'] = 'utf-8'

def extract_fb_dtsg(html: str) -> dict:
    patterns = {
        'DTSGInitialData_standard': r'"DTSGInitialData"[^}]*"token"[:\s]*"([^"]+)"',
        'DTSGInitialData_alt': r'"DTSGInitialData"\s*,\s*\{[^}]*"token"\s*:\s*"([^"]+)"',
        'fb_dtsg_literal': r'"fb_dtsg":"([^"]+)"',
        'fb_dtsg_unicode_escape': r'fb_dtsg\\x22:\\x22([^\\]+)',
        'fb_dtsg_url_encoded': r'fb_dtsg%22%3A%22([^%]+)',
        'fb_dtsg_raw_hex': r'fb_dtsg\\\\x22:\\\\x22([^\\\\]+)',
        '__dtsg_assign': r'__dtsg\s*=\s*["\']([^"\']+)["\']',
        'generic_long_token': r'"token"[:\s]*"([^"]{20,})"',
        'fb_dtsg_in_array': r'"fb_dtsg",[^]]*"([^"]+)"',
        'DTSGInitData_third': r'DTSGInitialData[^}]{0,500}?"token":"([^"]+)"',
    }
    results = {}
    for name, pat in patterns.items():
        m = re.search(pat, html)
        results[name] = m.group(1)[:60] if m else 'NOT_FOUND'
    return results


def extract_lsd(html: str) -> dict:
    patterns = {
        'LSD_array_token': r'"LSD",\s*\[\]\s*,\s*\{\s*"token"\s*:\s*"([^"]+)"',
        'LSD_array_alt': r'"LSD",\s*\[\s*\]\s*,\s*\{[^}]*"token":"([^"]+)"',
        'lsd_literal': r'"lsd":"([^"]+)"',
        'LSD_token_in_block': r'LSD[^}]*"token":"([^"]+)"',
        'LSD_token_in_block_alt': r'LSD[^}]{0,200}?"token":"([^"]+)"',
        '__LSD_assign': r'__LSD\s*=\s*["\']([^"\']+)["\']',
    }
    results = {}
    for name, pat in patterns.items():
        m = re.search(pat, html)
        results[name] = m.group(1)[:60] if m else 'NOT_FOUND'
    return results


def extract_all_tokens(html: str):
    tokens = {}
    for pat, name in [(r'csrf_token":"([^"]+)"', 'csrf_in_json'), (r'csrftoken=([^;]+)', 'csrf_cookie_pattern')]:
        m = re.search(pat, html)
        if m:
            tokens[name] = m.group(1)[:40]
    for pat in [r'"server_revision":(\d+)', r'"client_revision":(\d+)', r'"revision":(\d+)']:
        m = re.search(pat, html)
        if m:
            tokens['server_revision'] = m.group(1)
            break
    m = re.search(r'igx_www\$([a-f0-9]+)', html)
    if m:
        tokens['rollout_hash'] = m.group(1)
    if 'login' in html[:1000].lower() or 'Log in' in html[:2000]:
        tokens['redirect_to_login'] = 'YES'
    m = re.search(r'"__dyn"[^:]*:"([^"]+)"', html)
    if m:
        tokens['__dyn'] = m.group(1)[:80]
    m = re.search(r'"__csr"[^:]*:"([^"]+)"', html)
    if m:
        tokens['__csr'] = m.group(1)[:40]
    if 'report' in html.lower():
        tokens['report_keyword_found'] = 'YES'
    else:
        tokens['report_keyword_found'] = 'NO'
    # Check for ds_user_id in page
    m = re.search(r'"ds_user_id"\s*:\s*"(\d+)"', html)
    if m:
        tokens['ds_user_id_in_page'] = m.group(1)
    m = re.search(r'"userId"\s*:\s*"(\d+)"', html)
    if m:
        tokens['user_id_in_page'] = m.group(1)
    # check __INITIAL_STATE__
    m = re.search(r'window\.__INITIAL_STATE__\s*=\s*JSON\.parse\(\\?"([^"]+)"\)', html)
    if m:
        tokens['__INITIAL_STATE__'] = 'FOUND (will decode)'
    m = re.search(r'window\._sharedData\s*=\s*', html)
    if m:
        tokens['_sharedData'] = 'FOUND'
    return tokens


if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: python debug_extract.py <session_id>")
        sys.exit(1)
    
    session_id = sys.argv[1].strip()
    
    s = requests.Session()
    s.cookies.set('sessionid', session_id, domain='.instagram.com')
    s.cookies.set('ig_did', str(uuid.uuid4()).upper(), domain='.instagram.com')
    s.cookies.set('mid', str(uuid.uuid4())[:26], domain='.instagram.com')
    
    headers = {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36',
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'en-US,en;q=0.9',
    }
    
    print("#" * 60)
    print(f"DEBUG: Fetching instagram.com with session ID")
    print(f"Session ID: {session_id[:20]}...{session_id[-10:]}")
    print("#" * 60)
    
    resp = s.get('https://www.instagram.com/', headers=headers, timeout=20)
    html = resp.text
    
    print(f"\nStatus: {resp.status_code}")
    print(f"Final URL: {resp.url}")
    print(f"Response size: {len(html)} bytes")
    
    # Cookie dump
    print(f"\n--- COOKIES ---")
    for cookie in s.cookies:
        val = cookie.value[:40] if cookie.value else 'EMPTY'
        print(f"  {cookie.name} = {val}")
    
    csrf = s.cookies.get('csrftoken', '')
    print(f"\n  csrftoken: {'FOUND: ' + csrf[:20] if csrf else 'MISSING'}")
    ds_uid = s.cookies.get('ds_user_id', '')
    print(f"  ds_user_id: {'FOUND: ' + ds_uid if ds_uid else 'MISSING'}")
    
    # Extract all tokens
    print(f"\n--- FB_DTSG EXTRACTION ---")
    dtsg_results = extract_fb_dtsg(html)
    for name, val in dtsg_results.items():
        ok = '+' if val != 'NOT_FOUND' else '-'
        print(f"  [{ok}] {name}: {val}")
    
    print(f"\n--- LSD EXTRACTION ---")
    lsd_results = extract_lsd(html)
    for name, val in lsd_results.items():
        ok = '+' if val != 'NOT_FOUND' else '-'
        print(f"  [{ok}] {name}: {val}")
    
    print(f"\n--- PAGE TOKENS ---")
    tokens = extract_all_tokens(html)
    for name, val in tokens.items():
        print(f"  {name}: {val}")
    
    if 'login' in resp.url:
        print(f"\nWARNING: Redirected to login! Session is invalid.")
    
    with open('_debug_page.html', 'w', encoding='utf-8') as f:
        f.write(html)
    print(f"\nFull HTML saved to _debug_page.html ({len(html)} bytes)")