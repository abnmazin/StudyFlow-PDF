import requests
import uuid
import random
import time
import logging
import re
import json
from urllib.parse import quote, urlencode
from typing import Optional
import tempfile
import os

try:
    import telebot
    from telebot import formatting
    from telebot.types import InlineKeyboardMarkup, InlineKeyboardButton
except ImportError:
    print("telebot not installed, install: pip install pyTelegramBotAPI")
    raise

# ── Logging ──────────────────────────────────────────────────────────────────
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(message)s'
)
log = logging.getLogger(__name__)

# ── Config ────────────────────────────────────────────────────────────────────
OWNER_ID    = 385713228
TOKEN       = '1644721136:AAGswGqerNZntSvp9-yEZKF_SMjg1PgQ8VM'
IG_APP_ID   = '936619743392459'

# Endpoints
IG_REPORT_URL     = 'https://www.instagram.com/api/v1/web/reports/get_frx_prompt/'
IG_PROFILE_URL    = 'https://www.instagram.com/api/v1/users/web_profile_info/'
IG_GRAPHQL_URL    = 'https://www.instagram.com/api/graphql'
IG_BULK_ROUTE_URL = 'https://www.instagram.com/ajax/bulk-route-definitions/'
IG_BZ_URL         = 'https://www.instagram.com/ajax/bz'
IG_SSO_URL        = 'https://www.instagram.com/api/v1/web/fxcal/ig_sso_users/'

# GraphQL doc_ids (extracted from HAR - update periodically)
DOC_ID_PROFILE_PAGE = '27937681195819736'

MS_START = 'Hi boss who we fuck it today ?'
HELP_TEXT = """
Hi boss
1- لأضافه حسابات وهمية ارسل الامر
/login user:password
او
/ses Sessionid

2- عليك تحديد سليب قبل البدء بأرسال امر
/sle 5
الـ 5 يعني كل 5ثواني ابلاغ

3- ارسل يوزر - عدد الابلاغات
60k5 - 100 هكذا

4- حدد نوع الابلاغ
"""

REPORT_ACTIONS = {
    'spam':        'ig_spam_v3',
    'dontlike':    'ig_i_dont_like_it_v3',
    'self':        'suicide_or_self_harm_or_eating_disorder_concern',
    'health':      'selling_or_promoting_restricted_items',
    'drugs2':      'selling_or_promoting_restricted_items',
    'guns':        'selling_or_promoting_restricted_items',
    'animals':     'violence_hate_or_exploitation',
    'nudity':      'nudity_or_sexual_activity',
    'sexual':      'nudity_or_sexual_activity',
    'pri':         'nudity_or_sexual_activity',
    'chaild':      'nudity_or_sexual_activity',
    'hate':        'violence_hate_or_exploitation',
    'violence2':   'violence_hate_or_exploitation',
    'animalvo':    'violence_hate_or_exploitation',
    'death':       'violence_hate_or_exploitation',
    'dassh':       'violence_hate_or_exploitation',
    'me':          'ig_bullying_or_harassment_me_v3',
    'someone':     'ig_bullying_or_harassment_someone_i_know_v3',
    'someoneelse': 'ig_bullying_or_harassment_someone_else_v3',
    'scam':        'ig_product_scam_fraud_v2',
    'info':        'false_information',
}

# ── Helper functions ─────────────────────────────────────────────────────────
def escape_markdown(text: str) -> str:
    escape_chars = r'_*[]()~`>#+-=|{}.!'
    return ''.join(f'\\{c}' if c in escape_chars else c for c in str(text))


def compute_jazoest(token: str) -> str:
    return str(sum(ord(c) for c in token))


def extract_json_chunk(text: str, key: str) -> Optional[str]:
    """Extract a JSON string value from page HTML: "key":"value" or "key":"value"."""
    patterns = [
        rf'"{key}":\s*"([^"\\]*(?:\\.[^"\\]*)*)"',
        rf'"token":"([^"]+)"',
        rf'{key}":"([^"]+)"',
    ]
    for pat in patterns:
        m = re.search(pat, text)
        if m:
            return m.group(1)
    return None


def extract_fb_dtsg(html: str) -> str:
    """Extract fb_dtsg from Instagram page HTML using multiple patterns."""
    patterns = [
        r'"DTSGInitialData",\[\],{"token":"([^"]+)"',  # Most common 2025-2026
        r'"DTSGInitialData"\s*,\s*\[\s*\]\s*,\s*{\s*"token"\s*:\s*"([^"]+)"',
        r'fb_dtsg\\" value=\\"([^\\"]+)\\"',
        r'name="fb_dtsg" value="([^"]+)"',
        r'"fb_dtsg":"([^"]+)"',
        r'fb_dtsg&quot;:&quot;([^&]+)&quot;',
        r'"token":"([^"]+)"[^}]*"DTSGInitialData"',
    ]
    for pat in patterns:
        m = re.search(pat, html)
        if m:
            return m.group(1)
    return ''

def extract_lsd(html: str) -> str:
    """Extract LSD token from Instagram page HTML."""
    patterns = [
        r'"LSD",\[\],{"token":"([^"]+)"}',  # Most common 2025-2026
        r'"LSD"\s*,\s*\[\s*\]\s*,\s*{\s*"token"\s*:\s*"([^"]+)"',
        r'name="lsd" value="([^"]+)"',
        r'"lsd":"([^"]+)"',
        r'LSD&quot;:&quot;([^&]+)&quot;',
    ]
    for pat in patterns:
        m = re.search(pat, html)
        if m:
            return m.group(1)
    return ''

def extract_rollout_hash(html: str) -> Optional[str]:
    """Extract the rollout hash for bulk-route-definitions namespace."""
    # Look for something like igx_www$7c76e8ffe2a97ece
    m = re.search(r'igx_www\$([a-f0-9]+)', html)
    if m:
        return m.group(1)
    return None


class RateLimitError(Exception):
    pass


# ── Session store ─────────────────────────────────────────────────────────────
def load_sessions(path='ses') -> list[str]:
    try:
        with open(path, 'r') as f:
            return [line.strip() for line in f if line.strip() and not line.startswith('#')]
    except FileNotFoundError:
        return []


def save_sessions(sessions, path='ses'):
    with open(path, 'w') as f:
        for s in sessions:
            f.write(f"{s}\n")


def pick_session(sessions: list[str]) -> str:
    if not sessions:
        raise ValueError('No sessions available')
    return random.choice(sessions)


# ── Instagram Web Session (2026 HAR-based) ────────────────────────────────────
class IGWebSession:
    """Full Instagram Web Session Manager using 2026 HAR-derived patterns."""

    # Static hardcoded __dyn and __csr (these rarely change, scraped from working page)
    # If these fail, the session init extracts fresh ones from the page
    DEFAULT_DYN = '7xe6E5q5U5ObwKBAg5S1Dxu13wvoKewSAwHwNwcy0lW4o0B-q1ew6ywaq0yE460qe4o5-1ywOwa90Fwcy1yw9O0H8jwae4UaEW2G0AEco5G0zE5W09yyES1Twoob82ZwrUdUbGw4mwr86C1mwrd6goK10xKi2qi7E5y4U158KmUhw5nyEcE4y16wAw4XwRw'
    DEFAULT_CSR = ''

    def __init__(self, session_id: str, proxy: Optional[str] = None):
        self.session_id = session_id
        self.s = requests.Session()
        self.proxy = {'http': proxy, 'https': proxy} if proxy else None

        # Core tokens
        self.csrftoken   = ''
        self.www_claim   = '0'
        self.ajax_rev    = '1039855775'
        self.jazoest     = '26278'
        self.ds_user_id  = ''
        self.fb_dtsg     = ''
        self.lsd         = ''
        self.__dyn       = self.DEFAULT_DYN
        self.__csr       = self.DEFAULT_CSR
        self.__hsdp      = ''
        self.__hblp      = ''
        self.__sjsp      = ''
        self.__spin_r    = '1039855775'
        self.__spin_t    = str(int(time.time()))
        self.__hsi       = ''
        self.rollout_hash = ''
        self.actor_id    = '0'  # av parameter
        self.__req_counter = 0

        self.logging_extra = '{"navigation_chain":"PolarisFeedRoot:feedPage:1:via_cold_start"}'

        self._init_session()

    def _gen_hsi(self) -> str:
        """Generate __hsi parameter (19-digit hex-ish timestamp)."""
        return hex(int(time.time() * 1000000))[2:].zfill(19)[:19]

    def _gen_s(self) -> str:
        """Generate __s parameter: random segments."""
        return f'{random.randint(100000,999999)}:{random.randint(100000,999999)}:{random.randint(100000,999999)}'

    def _get_av(self) -> str:
        """Get actor ID (av) parameter."""
        if self.actor_id and self.actor_id != '0':
            return self.actor_id
        if self.ds_user_id:
            return self.ds_user_id
        return '0'

    def _init_session(self):
        """Complete session initialization with token extraction."""
        headers = {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36',
            'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
            'Accept-Language': 'en-US,en;q=0.9',
            'Accept-Encoding': 'gzip, deflate, br',
            'DNT': '1',
            'Connection': 'keep-alive',
            'Sec-Fetch-Dest': 'document',
            'Sec-Fetch-Mode': 'navigate',
            'Sec-Fetch-Site': 'none',
        }

        # Set cookies BEFORE request (HAR shows these are required)
        self.s.cookies.set('sessionid', self.session_id, domain='.instagram.com')
        self.s.cookies.set('ig_did', str(uuid.uuid4()), domain='.instagram.com')
        self.s.cookies.set('mid', str(uuid.uuid4())[:26], domain='.instagram.com')
        self.s.cookies.set('ig_nrcb', '1', domain='.instagram.com')  # NEW: required 2026
        
        resp = self.s.get('https://www.instagram.com/', headers=headers, 
                          proxies=self.proxy, timeout=15)
        
        # Extract tokens from response
        self.csrftoken = self.s.cookies.get('csrftoken', 'missing')
        if not self.csrftoken:
            # Try from Set-Cookie header
            set_cookie = resp.headers.get('Set-Cookie', '')
            if 'csrftoken=' in set_cookie:
                self.csrftoken = set_cookie.split('csrftoken=')[1].split(';')[0]
        if not self.csrftoken:
            # Try from HTML
            csrf_match = re.search(r'"csrf_token":"([^"]+)"', resp.text)
            if csrf_match:
                self.csrftoken = csrf_match.group(1)
        
        self.fb_dtsg = extract_fb_dtsg(resp.text)
        self.lsd = extract_lsd(resp.text)

        # If critical tokens missing, dump HTML for debugging
        if not self.csrftoken or not self.fb_dtsg:
            temp_dir = tempfile.gettempdir()
            debug_file = os.path.join(temp_dir, f'ig_debug_{int(time.time())}.html')
            with open(debug_file, 'w', encoding='utf-8') as f:
                f.write(resp.text)
            log.error('Missing tokens! HTML dumped to %s', debug_file)
            log.error('Response status: %d, Content-Length: %s', 
                     resp.status_code, resp.headers.get('Content-Length'))
        
        # Extract ds_user_id from sessionid
        if '%3A' in self.session_id:
            self.ds_user_id = self.session_id.split('%3A')[0]
        elif ':' in self.session_id:
            self.ds_user_id = self.session_id.split(':')[0]
        
        # Extract revision from page
        rev_patterns = [
            r'"server_revision":(\d+)',
            r'"client_revision":(\d+)',
            r'"revision":(\d+)',
        ]
        for pat in rev_patterns:
            m = re.search(pat, resp.text)
            if m:
                self.ajax_rev = m.group(1)
                break
        if not self.ajax_rev:
            self.ajax_rev = '1039855775'  # Fallback from HAR
        
        # Compute jazoest from fb_dtsg (not csrftoken!)
        if self.fb_dtsg:
            self.jazoest = str(sum(ord(c) for c in self.fb_dtsg))
        else:
            self.jazoest = '26278'  # Fallback
        
        # Log ALL tokens for debugging
        log.info('Session init | csrf=%s | dtsg=%s | lsd=%s | rev=%s | uid=%s',
                 self.csrftoken[:8] if self.csrftoken else 'NONE',
                 self.fb_dtsg[:20] + '...' if self.fb_dtsg and len(self.fb_dtsg) > 20 else (self.fb_dtsg or 'NONE'),
                 self.lsd[:15] + '...' if self.lsd and len(self.lsd) > 15 else (self.lsd or 'NONE'),
                 self.ajax_rev,
                 self.ds_user_id[:8] if self.ds_user_id else 'NONE')

    def validate_session(self) -> bool:
        """Quick validation that session has all required tokens."""
        if not self.csrftoken:
            log.error('Validation failed: no csrftoken')
            return False
        if not self.fb_dtsg:
            log.error('Validation failed: no fb_dtsg')
            return False
        if not self.lsd:
            log.error('Validation failed: no lsd')
            return False
        return True

    def web_headers(self, need_claim: bool = False) -> dict:
        h = {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36',
            'Accept': '*/*',
            'Accept-Language': 'en-US,en;q=0.9',
            'Accept-Encoding': 'gzip, deflate, br',
            'Content-Type': 'application/x-www-form-urlencoded',
            'Origin': 'https://www.instagram.com',
            'Referer': 'https://www.instagram.com/',
            'X-CSRFToken': self.csrftoken,
            'X-IG-App-ID': IG_APP_ID,
            'X-Instagram-AJAX': self.ajax_rev,
            'X-Requested-With': 'XMLHttpRequest',
            'X-FB-LSD': self.lsd,  # CRITICAL: was missing
            'Sec-Fetch-Dest': 'empty',
            'Sec-Fetch-Mode': 'cors',
            'Sec-Fetch-Site': 'same-origin',
            'X-ASBD-ID': '359341',
        }
        if need_claim and not self.www_claim:
            self._fetch_www_claim_via_sso()
        
        headers = self.web_headers(need_claim)
        
        try:
            return headers
        except requests.exceptions.RequestException as e:
            log.warning('Request failed: %s', e)
            return {}

    def _build_comet_params(self, extra_params: dict = None) -> dict:
        """Build the full set of Comet/Relay protocol parameters."""
        self.__req_counter += 1
        params = {
            'av': self._get_av(),
            '__d': 'www',
            '__user': '0',
            '__a': '1',
            '__req': str(self.__req_counter),
            '__hs': self.__hsdp or '',
            'dpr': '1',
            '__ccg': 'GOOD',
            '__rev': self.ajax_rev,
            '__s': self._gen_s(),
            '__hsi': self.__hsi or self._gen_hsi(),
            '__dyn': self.__dyn or self.DEFAULT_DYN,
            '__csr': self.__csr or '',
            '__hsdp': self.__hsdp or '',
            '__hblp': self.__hblp or '',
            '__sjsp': self.__sjsp or '',
            '__comet_req': '7',
            'fb_dtsg': self.fb_dtsg or 'NA',
            'jazoest': self.jazoest,
            'lsd': self.lsd,
            '__spin_r': self.__spin_r,
            '__spin_b': 'trunk',
            '__spin_t': str(int(time.time())),
            '__crn': 'comet.igweb.PolarisFeedRoute',
            'fb_api_caller_class': 'RelayModern',
            'fb_api_req_friendly_name': 'PolarisProfilePageContentQuery',
            'server_timestamps': 'true',
            'variables': variables,
            'doc_id': '27937681195819736',  # From HAR
        }

        if extra_params:
            params.update(extra_params)

        return params

    def _request_with_retry(self, method, url, max_retries=5, **kwargs):
        for attempt in range(max_retries):
            try:
                resp = self.s.request(method, url, proxies=self.proxy, **kwargs)

                # Handle 429 with exponential backoff + jitter
                if resp.status_code == 429:
                    wait = min(2 ** attempt * 3 + random.uniform(1, 5), 120)
                    log.warning('Rate limited (429), waiting %.1fs (attempt %d/%d)',
                              wait, attempt + 1, max_retries)

                    # If rate-limited hard, try to refresh www_claim
                    if attempt >= 2:
                        self._fetch_www_claim_via_sso()

                    time.sleep(wait)
                    continue

                # Handle challenge/checkpoint
                if resp.status_code == 400 and ('checkpoint' in resp.text.lower() or 'challenge' in resp.text.lower()):
                    log.error('Account checkpoint/challenge required')
                    raise RateLimitError('Account checkpoint required')

                resp.raise_for_status()
                return resp

            except requests.exceptions.HTTPError as e:
                if e.response.status_code == 429 and attempt < max_retries - 1:
                    continue
                raise
            except requests.exceptions.ConnectionError as e:
                if attempt < max_retries - 1:
                    wait = 5 + random.uniform(1, 5)
                    log.warning('Connection error, retrying in %.1fs: %s', wait, e)
                    time.sleep(wait)
                    continue
                raise
            except requests.exceptions.Timeout as e:
                if attempt < max_retries - 1:
                    log.warning('Timeout, retrying: %s', e)
                    continue
                raise

        raise RateLimitError(f'Max retries exceeded after {max_retries} attempts')

    def _ensure_www_claim(self):
        """Ensure we have a valid www_claim before making claims-required requests."""
        if not self.www_claim or self.www_claim == '0':
            self._fetch_www_claim_via_sso()

    def post(self, url: str, data: dict, add_comet_params: bool = False) -> dict:
        """POST with optional Comet protocol parameters."""
        headers = self.web_headers()

        if add_comet_params:
            self._ensure_www_claim()
            # For GraphQL-style POST, merge comet params into data
            comet = self._build_comet_params()
            comet.update(data)
            final_data = comet
        else:
            final_data = data

        resp = self._request_with_retry(
            'POST', url,
            data=final_data,
            headers=headers,
            timeout=20
        )

        # Update www_claim from response
        claim = resp.headers.get('X-IG-Set-WWW-Claim')
        if claim:
            self.www_claim = claim

        try:
            return resp.json()
        except json.JSONDecodeError:
            log.error('JSON decode error: %s', resp.text[:300])
            return {'status': 'error', 'raw': resp.text[:500]}

    def get_json(self, url: str, params: dict = None) -> dict:
        """GET request returning JSON."""
        headers = self.web_headers()

        resp = self._request_with_retry(
            'GET', url,
            params=params,
            headers=headers,
            timeout=15
        )

        claim = resp.headers.get('X-IG-Set-WWW-Claim')
        if claim:
            self.www_claim = claim

        try:
            return resp.json()
        except json.JSONDecodeError:
            log.error('JSON decode error: %s', resp.text[:300])
            return {'status': 'error', 'raw': resp.text[:500]}

    def _fetch_www_claim_via_sso(self):
        """Fetch the X-IG-WWW-Claim token needed for some API calls."""
        try:
            # This endpoint is often used to get a claim token.
            claim_url = 'https://i.instagram.com/api/v1/bloks/apps/com.bloks.www.bloks.caa.login.async.sso/'
            params = {
                'bootstrap_version': '5',
                'device_id': str(uuid.uuid4()),
            }
            headers = {
                'User-Agent': self.web_headers()['User-Agent'],
                'Accept': '*/*',
                'Accept-Language': 'en-US,en;q=0.9',
                'X-IG-App-ID': IG_APP_ID,
                'Connection': 'keep-alive',
            }
            
            resp = self.s.get(claim_url, headers=headers, params=params, proxies=self.proxy, timeout=10)
            
            if resp.status_code == 200 and 'x-ig-set-www-claim' in resp.headers:
                self.www_claim = resp.headers['x-ig-set-www-claim']
                log.info('Fetched new www_claim: %s...', self.www_claim[:20])
            else:
                log.warning('Failed to fetch www_claim. Status: %d', resp.status_code)
                self.www_claim = '0' # Fallback to avoid repeated attempts
        except requests.exceptions.RequestException as e:
            log.error('Error fetching www_claim: %s', e)
            self.www_claim = '0' # Fallback

    def get_user_id(self, username: str) -> str:
        """Get user ID using GraphQL PolarisProfilePageContentQuery (from HAR)."""
        variables = json.dumps({
            "id": username,
            "render_surface": "PROFILE", 
            "enable_integrity_filters": True
        })
        
        # Generate __s parameter (HAR format: yme7sc:rmim2r:da4cit)
        rand_seg = lambda: ''.join(random.choices('abcdefghijklmnopqrstuvwxyz0123456789', k=6))
        __s = f"{rand_seg()}:{rand_seg()}:{rand_seg()}"
        
        data = {
            'av': self.ds_user_id or '0',
            '__d': 'www',
            '__user': '0',
            '__a': '1',
            '__req': '1',
            '__hs': '20593.HYP:instagram_web_pkg.2.1...0',  # From HAR
            'dpr': '1',
            '__ccg': 'GOOD',
            '__rev': self.ajax_rev,
            '__s': __s,
            '__hsi': str(random.randint(7000000000000000000, 8000000000000000000)),
            '__dyn': '7xe6E5q5U5ObwKBAg5S1Dxu13wvoKewSAwHwNwcy0lW4o0B-q1ew6ywaq0yE460qe4o5-1ywOwa90Fwcy1yw9O0H8jwae4UaEW2G0AEco5G0zE5W09yyES1Twoob82ZwrUdUbGw4mwr86C1mwrd6goK10xKi2qi7E5y4U158KmUhw5nyEcE4y16wAw4XwRw',
            '__csr': '',
            '__hsdp': 'nMBi12pOWA2MSbARnPZ99devHcmWt2p2BJGEB0xwHucV48vAjAyEW6VSh2ElYM4C4S6j5Ao8msE4a9w9F3U5G1OAwCwTxa4UZ0AxS0-UK6EbUhwFwnEuGu3a2658S5Hwci5EeEC2i0O8Sdw9i3-fx60zoC5K1rx-05-Ukw19906Nw3RE560o-0dbwGw4Nw14O0h902go9oNAx209ww',
            '__hblp': '08G0PEW2u1CwcWEK2u1vK2y5SawnE8oeomAz8hDDwLyVE9U8onBwpE4u2a2CbxG2-4oaoqwgUpHGu3aEuxidBx2Vo4uq12wIxq3G9wAwdqdwoUW263KU-aCw8S9z8C15xuaxi1RwYwda0om08kwdG580SS1Mwbd0d60Co4m3l2U9rw3qoa8a824w9q1Og0QK2G0j6681Do1xE13EC0gx0ei1LweO7FENAx20ji0iK',
            '__sjsp': 'nMBi12pOWA2MSbARnRRQAAQUCIMCDgCgFrqG9g8oaTzeh27V4V8GexKtAgG5vc1toaA',
            '__comet_req': '7',
            'fb_dtsg': self.fb_dtsg,  # CRITICAL
            'jazoest': self.jazoest,
            'lsd': self.lsd,  # CRITICAL
            '__spin_r': self.ajax_rev,
            '__spin_b': 'trunk',
            '__spin_t': str(int(time.time())),
            '__crn': 'comet.igweb.PolarisFeedRoute',
            'fb_api_caller_class': 'RelayModern',
            'fb_api_req_friendly_name': 'PolarisProfilePageContentQuery',
            'server_timestamps': 'true',
            'variables': variables,
            'doc_id': DOC_ID_PROFILE_PAGE,  # From HAR
        }
        
        resp = self.post(IG_GRAPHQL_URL, data, need_claim=True)
        
        # Extract user ID from response
        user_data = resp.get('data', {}).get('user', {})
        if user_data:
            return str(user_data.get('id', user_data.get('pk', '')))
        
        raise ValueError('Could not resolve user ID via GraphQL')

    def get_user_id_graphql(self, username: str) -> str:
        """Get user ID using GraphQL query (matches HAR). Falls back to this."""
        variables = json.dumps({
            "id": username,
            "render_surface": "PROFILE",
            "enable_integrity_filters": True
        })

        data = {
            'variables': variables,
            'doc_id': DOC_ID_PROFILE_PAGE,
            'server_timestamps': 'true',
            'fb_api_caller_class': 'RelayModern',
            'fb_api_req_friendly_name': 'PolarisProfilePageContentQuery',
        }

        result = self.post(IG_GRAPHQL_URL, data, add_comet_params=True)

        # Parse graphql response
        user_data = result.get('data', {}).get('user', {})
        if user_data:
            return str(user_data.get('id', ''))

        raise ValueError(f'Could not resolve user ID via GraphQL: {result}')

    def get_follower_count(self, username: str) -> int:
        url = f'{IG_PROFILE_URL}?username={username}'
        data = self.get_json(url)

        if data.get('status') != 'ok':
            return 0

        user = data.get('data', {}).get('user', {})
        edge = user.get('edge_followed_by', {})
        return edge.get('count', 0)


def make_web_session(sessions: list[str], proxy: Optional[str] = None) -> IGWebSession:
    return IGWebSession(pick_session(sessions), proxy=proxy)


# ── Reporter ─────────────────────────────────────────────────────────────────
class Reporter:
    def __init__(self, bot, sessions: list[str], proxies: list[str] = None):
        self.bot       = bot
        self.sessions  = sessions
        self.proxies   = proxies or []
        self.running   = False
        self.good      = 0
        self.bad       = 0
        self.user_id_cache = {}

    def _get_proxy(self) -> Optional[str]:
        if not self.proxies:
            return None
        return random.choice(self.proxies)

    def _do_report_once(self, ig: IGWebSession, user_id: str, final_tag: str) -> bool:
        """Perform one report chain with proper Comet protocol."""
        
        # Ensure all tokens are valid before reporting
        if not ig.fb_dtsg or not ig.lsd:
            log.error('Missing fb_dtsg or lsd, cannot report')
            return False
        
        base_data = {
            'av': ig.ds_user_id,
            '__d': 'www',
            '__user': '0',
            '__a': '1',
            '__req': str(random.randint(1, 99)),
            '__hs': '20593.HYP:instagram_web_pkg.2.1...0',
            'dpr': '1',
            '__ccg': 'GOOD',
            '__rev': ig.ajax_rev,
            '__s': f"{random.randint(100000,999999)}:{random.randint(100000,999999)}:{random.randint(100000,999999)}",
            '__hsi': str(random.randint(7000000000000000000, 8000000000000000000)),
            '__dyn': '7xe6E5q5U5ObwKBAg5S1Dxu13wvoKewSAwHwNwcy0lW4o0B-q1ew6ywaq0yE460qe4o5-1ywOwa90Fwcy1yw9O0H8jwae4UaEW2G0AEco5G0zE5W09yyES1Twoob82ZwrUdUbGw4mwr86C1mwrd6goK10xKi2qi7E5y4U158KmUhw5nyEcE4y16wAw4XwRw',
            '__csr': '',
            '__hsdp': 'nMBi12pOWA2MSbARnPZ99devHcmWt2p2BJGEB0xwHucV48vAjAyEW6VSh2ElYM4C4S6j5Ao8msE4a9w9F3U5G1OAwCwTxa4UZ0AxS0-UK6EbUhwFwnEuGu3a2658S5Hwci5EeEC2i0O8Sdw9i3-fx60zoC5K1rx-05-Ukw19906Nw3RE560o-0dbwGw4Nw14O0h902go9oNAx209ww',
            '__hblp': ':360,503',
            '__sjsp': 'nMBi12pOWA2MSbARnRRQAAQUCIMCDgCgFrqG9g8oaTzeh27V4V8GexKtAgG5vc1toaA',
            '__comet_req': '7',
            'fb_dtsg': ig.fb_dtsg,
            'jazoest': ig.jazoest,
            'lsd': ig.lsd,
            '__spin_r': ig.ajax_rev,
            '__spin_b': 'trunk',
            '__spin_t': str(int(time.time())),
            '__crn': 'comet.igweb.PolarisFeedRoute',
            'container_module': 'profilePage',
            'entry_point': '1',
            'location': '2',
            'object_id': user_id,
            'object_type': '5',
            'logging_extra': '{"navigation_chain":"PolarisFeedRoot:feedPage:1:via_cold_start"}',
        }
        
        # Step 1 – open report
        data1 = {**base_data, 'frx_prompt_request_type': '1'}
        r1 = ig.post(IG_REPORT_URL, data1)
        if r1.get('status') != 'ok':
            log.warning('Step 1 failed: %s', r1.get('message', 'Unknown'))
            return False
        
        ctx = r1.get('response', {}).get('context', '')
        if not ctx:
            log.warning('No context in step 1 response')
            return False
        
        # Step 2 – report account
        data2 = {**base_data, 'context': ctx, 'selected_tag_types': '["ig_report_account"]', 'frx_prompt_request_type': '2'}
        r2 = ig.post(IG_REPORT_URL, data2)
        if r2.get('status') != 'ok':
            return False
        ctx = r2.get('response', {}).get('context', '')

        # Step 3 – inappropriate content
        data3 = {**base_data, 'context': ctx, 'selected_tag_types': '["ig_its_inappropriate"]', 'frx_prompt_request_type': '2'}
        r3 = ig.post(IG_REPORT_URL, data3)
        if r3.get('status') != 'ok':
            return False
        ctx = r3.get('response', {}).get('context', '')

        # Step 4 – choose category
        data4 = {**base_data, 'context': ctx, 'selected_tag_types': f'["{final_tag}"]', 'frx_prompt_request_type': '2'}
        r4 = ig.post(IG_REPORT_URL, data4)
        
        return r4.get('type') == 2 or r4.get('status') == 'ok'

    def report(self, username: str, report_tag: str, count: int, chat_id: int, msg_id: int, sleep: int):
        self.running = True
        self.good = 0
        self.bad = 0

        safe_user = escape_markdown(username)

        def status_text(extra=''):
            base = f'{formatting.mbold("Username")} : @{safe_user}\nDone {self.good} : Bad {self.bad}'
            return base + (f'\n{extra}' if extra else '')

        # Initialize session with proxy
        proxy = self._get_proxy()
        try:
            ig = make_web_session(self.sessions, proxy=proxy)

            # Get user ID with caching
            if username in self.user_id_cache:
                user_id = self.user_id_cache[username]
                log.info('Using cached user_id for %s', username)
            else:
                try:
                    user_id = ig.get_user_id(username)
                except Exception as e:
                    log.warning('web_profile_info failed, trying GraphQL: %s', e)
                    user_id = ig.get_user_id_graphql(username)
                self.user_id_cache[username] = user_id
                log.info('Resolved %s -> %s', username, user_id)

        except Exception as e:
            log.error('Cannot resolve user_id for %s: %s', username, e)
            err_msg = escape_markdown(str(e))
            try:
                self.bot.edit_message_text(
                    status_text(f'Error: {err_msg}\nلايوجد حسابات وهمية'),
                    chat_id, msg_id, parse_mode='MarkdownV2'
                )
            except:
                pass
            self.running = False
            return

        # Reporting loop
        for i in range(1, count + 1):
            if not self.running:
                break

            try:
                success = self._do_report_once(ig, user_id, report_tag)
                if success:
                    self.good += 1
                    log.info('Report %d/%d succeeded for %s', i, count, username)
                else:
                    self.bad += 1
                    log.warning('Report %d/%d failed for %s', i, count, username)

            except RateLimitError as e:
                log.warning('Rate limited on attempt %d: %s', i, e)
                self.bad += 1

                # Rotate session on rate limit + try fresh init
                try:
                    proxy = self._get_proxy()
                    ig = make_web_session(self.sessions, proxy=proxy)
                    log.info('Rotated to new session for attempt %d', i)
                    time.sleep(5)
                except Exception as session_e:
                    log.error('No more sessions: %s', session_e)
                    self.running = False
                    break

            except Exception as e:
                log.warning('Report attempt %d failed: %s', i, e)
                self.bad += 1

            # Update status every 5 reports
            if i % 5 == 0 or i == count or not self.running:
                try:
                    self.bot.edit_message_text(
                        status_text(), chat_id, msg_id,
                        reply_markup=self._runn_markup(), parse_mode='MarkdownV2'
                    )
                except:
                    pass

            if i < count and self.running:
                actual_sleep = max(1, sleep + random.uniform(-0.5, 1.5))
                time.sleep(actual_sleep)

        label = 'Stopped' if not self.running else 'Done'
        try:
            self.bot.edit_message_text(
                status_text(label), chat_id, msg_id,
                reply_markup=self._done_markup(), parse_mode='MarkdownV2'
            )
        except:
            pass
        self.running = False

    def _runn_markup(self):
        markup = InlineKeyboardMarkup()
        markup.add(InlineKeyboardButton('⏹ Stop', callback_data='stop'))
        return markup

    def _done_markup(self):
        markup = InlineKeyboardMarkup()
        markup.add(InlineKeyboardButton('🔙 Back', callback_data='back'))
        return markup


# ── Bot setup ─────────────────────────────────────────────────────────────────
class BandBot:
    def __init__(self):
        self.bot      = telebot.TeleBot(TOKEN)
        self.sessions = load_sessions()
        self.proxies  = []
        self.reporter = Reporter(self.bot, self.sessions, self.proxies)
        self.sleep    = 5
        self.target   = None
        self._register_handlers()

    def _safe_username(self, username: str) -> str:
        return escape_markdown(username)

    def _user_info_text(self, username: str) -> str:
        safe = self._safe_username(username)
        try:
            proxy = random.choice(self.proxies) if self.proxies else None
            ig = IGWebSession(pick_session(self.sessions), proxy=proxy)
            count = ig.get_follower_count(username)
            return (
                f'{formatting.mbold("Username")} : @{safe}\n'
                f'{formatting.mbold("Followers")} : {count}'
            )
        except Exception as e:
            log.warning('Follower count failed: %s', e)
            return f'{formatting.mbold("Username")} : @{safe}'

    def _register_handlers(self):
        bot = self.bot

        @bot.message_handler(commands=['start'])
        def start(msg):
            if msg.from_user.id != OWNER_ID:
                bot.send_message(msg.chat.id, 'Unauthorized')
                return
            bot.send_message(OWNER_ID, MS_START)

        @bot.message_handler(commands=['help'])
        def help_cmd(msg):
            if msg.from_user.id != OWNER_ID:
                return
            bot.send_message(msg.chat.id, HELP_TEXT)

        @bot.message_handler(commands=['sle'])
        def set_sleep(msg):
            if msg.from_user.id != OWNER_ID:
                return
            try:
                self.sleep = int(msg.text.split('/sle')[1].strip())
                bot.send_message(msg.chat.id, f'تم تعين السليب {self.sleep}')
            except (ValueError, IndexError):
                bot.send_message(msg.chat.id, 'استخدام صحيح: /sle 5')

        @bot.message_handler(commands=['ses'])
        def add_session(msg):
            if msg.from_user.id != OWNER_ID:
                return
            text = msg.text
            if 'check' in text.lower():
                self._check_sessions(msg)
            else:
                try:
                    sid = text.split('/ses')[1].strip()
                    if not sid:
                        raise ValueError
                    self.sessions.append(sid)
                    save_sessions(self.sessions)
                    bot.send_message(msg.chat.id, 'تمت اضافه سشن ايدي')
                except (ValueError, IndexError):
                    bot.send_message(msg.chat.id, 'استخدام صحيح: /ses <session_id>')

        @bot.message_handler(commands=['proxy'])
        def add_proxy(msg):
            if msg.from_user.id != OWNER_ID:
                return
            try:
                px = msg.text.split('/proxy')[1].strip()
                if not px:
                    raise ValueError
                self.proxies.append(px)
                bot.send_message(msg.chat.id, f'تمت اضافه بروكسي\nالعدد: {len(self.proxies)}')
            except (ValueError, IndexError):
                bot.send_message(msg.chat.id, 'استخدام صحيح: /proxy http://ip:port')

        @bot.message_handler(commands=['login'])
        def login(msg):
            if msg.from_user.id != OWNER_ID:
                return
            try:
                creds = msg.text.split('/login')[1].strip()
                username, password = creds.split(':', 1)
                sid = self._instagram_login(username.strip(), password.strip())
                if sid:
                    self.sessions.append(sid)
                    save_sessions(self.sessions)
                    bot.send_message(OWNER_ID, 'تمت اضافه الحساب')
                else:
                    bot.send_message(OWNER_ID, 'فشل تسجيل الدخول')
            except (ValueError, IndexError):
                bot.send_message(msg.chat.id, 'استخدام صحيح: /login user:password')

        @bot.message_handler(content_types=['text'])
        def set_target(msg):
            if msg.from_user.id != OWNER_ID:
                return
            try:
                parts = msg.text.split('-', 1)
                username = parts[0].strip()
                count = int(parts[1].strip())
                self.target = (username, count)
                text = self._user_info_text(username)

                markup = InlineKeyboardMarkup(row_width=2)
                markup.add(
                    InlineKeyboardButton('🚫 Spam', callback_data='spam'),
                    InlineKeyboardButton('👤 Self Harm', callback_data='self'),
                    InlineKeyboardButton('💊 Drugs', callback_data='drugs2'),
                    InlineKeyboardButton('🔞 Nudity', callback_data='nudity'),
                    InlineKeyboardButton('😡 Hate', callback_data='hate'),
                    InlineKeyboardButton('🤬 Bullying', callback_data='me'),
                    InlineKeyboardButton('💰 Scam', callback_data='scam'),
                    InlineKeyboardButton('❓ Help', callback_data='help'),
                )

                bot.send_message(OWNER_ID, text, parse_mode='MarkdownV2', reply_markup=markup)
            except (ValueError, IndexError):
                bot.send_message(msg.chat.id, 'ارسل اليوزر بهذا الترتيب\n60k5 - 100')

        @bot.callback_query_handler(func=lambda call: True)
        def callback(call):
            self._handle_callback(call)

    def _handle_callback(self, call):
        text = call.data
        cid = call.from_user.id
        mid = call.message.message_id

        if cid != OWNER_ID:
            self.bot.answer_callback_query(call.id, 'Unauthorized')
            return

        if text == 'help':
            self.bot.edit_message_text(HELP_TEXT, cid, mid)
            return
        if text == 'back':
            self.bot.edit_message_text(MS_START, cid, mid)
            return
        if text == 'stop':
            self.reporter.running = False
            self.bot.answer_callback_query(call.id, 'Stopping...')
            return

        if text in REPORT_ACTIONS:
            if not self.target:
                self.bot.answer_callback_query(call.id, 'حدد اليوزر اولا')
                return
            if not self.sessions:
                self.bot.answer_callback_query(call.id, 'اضف حساب وهمي اولا')
                return

            username, count = self.target
            report_tag = REPORT_ACTIONS[text]
            safe = self._safe_username(username)

            self.bot.edit_message_text(
                f'{formatting.mbold("Username")} : @{safe}',
                cid, mid, reply_markup=self.reporter._runn_markup(), parse_mode='MarkdownV2'
            )

            import threading
            t = threading.Thread(
                target=self.reporter.report,
                args=(username, report_tag, count, cid, mid, self.sleep)
            )
            t.daemon = True
            t.start()

    def _instagram_login(self, username: str, password: str) -> Optional[str]:
        """Modern web login using /ajax/ endpoint."""
        uid = str(uuid.uuid4())

        s = requests.Session()
        s.get('https://www.instagram.com/')
        csrf = s.cookies.get('csrftoken', 'missing')

        headers = {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36',
            'X-CSRFToken': csrf,
            'X-IG-App-ID': IG_APP_ID,
            'X-Requested-With': 'XMLHttpRequest',
            'Referer': 'https://www.instagram.com/',
            'Content-Type': 'application/x-www-form-urlencoded',
        }

        data = {
            'username': username,
            'enc_password': f'#PWD_INSTAGRAM_BROWSER:0:{int(time.time())}:{password}',
            'queryParams': '{}',
            'optIntoOneTap': 'false',
            'stopDeletionNonce': '',
            'trustedDeviceRecords': '{}',
        }

        try:
            resp = s.post(
                'https://www.instagram.com/api/v1/web/accounts/login/ajax/',
                data=data, headers=headers, timeout=15
            )
            result = resp.json()

            if result.get('authenticated') or result.get('userId'):
                sessionid = s.cookies.get('sessionid')
                if sessionid:
                    log.info('Login success for %s', username)
                    return sessionid

            log.warning('Login failed for %s: %s', username, result)

            if result.get('checkpoint_url'):
                log.error('Checkpoint required for %s', username)

        except Exception as e:
            log.error('Login error: %s', e)

        return None

    def _check_sessions(self, msg):
        valid = []
        invalid = []
        for sid in self.sessions:
            try:
                ig = IGWebSession(sid)
                if ig.csrftoken and ig.fb_dtsg:
                    valid.append(sid)
                else:
                    invalid.append(sid)
            except Exception as e:
                invalid.append(sid)

        self.sessions[:] = valid
        save_sessions(self.sessions)

        token_status = ''
        if valid:
            try:
                test_ig = IGWebSession(valid[0])
                has_lsd = '✅ lsd' if test_ig.lsd else '⚠️ No lsd'
                has_fb_dtsg = '✅ dtsg' if test_ig.fb_dtsg else '⚠️ No dtsg'
                has_claim = '✅ claim' if test_ig.www_claim and test_ig.www_claim != '0' else '⚠️ No claim'
                token_status = f'{has_fb_dtsg} | {has_lsd} | {has_claim}'
            except Exception as e:
                token_status = f'❌ Error: {e}'

        self.bot.send_message(
            msg.chat.id,
            f'تم فحص السشنات\n✅ صالح: {len(valid)}\n❌ فاسد: {len(invalid)}\n{token_status}'
        )

    def run(self):
        log.info('Bot starting...')
        try:
            self.bot.send_message(OWNER_ID, 'Bot started ✅')
        except:
            pass

        while True:
            try:
                self.bot.polling(none_stop=True, timeout=30, interval=1)
            except Exception as e:
                log.error('Polling error: %s', e)
                time.sleep(5)


if __name__ == '__main__':
    BandBot().run()