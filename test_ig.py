import requests
import re
import json
import time
import uuid
import random
import logging

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s [%(levelname)s] %(message)s')
log = logging.getLogger()

# Constants from the original script
IG_APP_ID = '936619743392459'
IG_GRAPHQL_URL = 'https://www.instagram.com/api/graphql'

from bs4 import BeautifulSoup

def extract_from_json_or_script(html: str, key: str):
    # Try to find in JSON-like script tags
    try:
        soup = BeautifulSoup(html, 'html.parser')
        for script in soup.find_all('script', type='application/json'):
            data = json.loads(script.string)
            if key in data:
                return data[key]
    except Exception:
        pass

    # Fallback to regex
    patterns = [
        fr'"{key}":"([^"]+)"',
        fr'"{key}",\[\],{{"token":"([^"]+)"}}'
    ]
    for pat in patterns:
        m = re.search(pat, html)
        if m:
            return m.group(1)
    return ''

def extract_fb_dtsg(html: str) -> str:
    """Extract fb_dtsg from Instagram page HTML using multiple patterns."""
    token = extract_from_json_or_script(html, 'DTSGInitialData')
    if token and isinstance(token, dict):
        return token.get('token', '')
    
    patterns = [
        r'"DTSGInitialData",\[\],{"token":"([^"]+)"',
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
    token = extract_from_json_or_script(html, 'LSD')
    if token and isinstance(token, dict):
        return token.get('token', '')

    patterns = [
        r'"LSD",\[\],{"token":"([^"]+)"}',
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

class IGWebSession:
    def __init__(self, session_id: str, proxy: dict = None):
        self.session_id = session_id
        self.s = requests.Session()
        self.proxy = proxy
        self.csrftoken = None
        self.fb_dtsg = None
        self.lsd = None
        self.ajax_rev = None
        self.ds_user_id = None
        self.jazoest = None
        self.www_claim = None
        self._init_session()

    def _init_session(self):
        headers = {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36',
            'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
            'Accept-Language': 'en-US,en;q=0.9',
            'Accept-Encoding': 'gzip, deflate, br',
            'DNT': '1',
            'Connection': 'keep-alive',
        }
        
        self.s.cookies.set('sessionid', self.session_id, domain='.instagram.com')
        self.s.cookies.set('ig_did', str(uuid.uuid4()), domain='.instagram.com')
        self.s.cookies.set('mid', str(uuid.uuid4())[:26], domain='.instagram.com')
        self.s.cookies.set('ig_nrcb', '1', domain='.instagram.com')
        
        try:
            # First request to get initial cookies and headers
            initial_resp = self.s.get('https://www.instagram.com/', headers=headers, proxies=self.proxy, timeout=15)
            initial_resp.raise_for_status()

            # Second request to an endpoint that provides the tokens
            bz_url = 'https://www.instagram.com/ajax/bz'
            resp = self.s.post(bz_url, headers=self.web_headers(), proxies=self.proxy, timeout=15)
            resp.raise_for_status()

        except requests.RequestException as e:
            log.error(f"Failed to connect to Instagram: {e}")
            return

        # CSRF Token
        self.csrftoken = self.s.cookies.get('csrftoken')
        if not self.csrftoken:
            set_cookie = resp.headers.get('Set-Cookie', '')
            if 'csrftoken=' in set_cookie:
                self.csrftoken = set_cookie.split('csrftoken=')[1].split(';')[0]
        if not self.csrftoken:
            csrf_match = re.search(r'"csrf_token":"([^"]+)"', resp.text)
            if csrf_match:
                self.csrftoken = csrf_match.group(1)

        self.fb_dtsg = extract_fb_dtsg(resp.text)
        self.lsd = extract_lsd(resp.text)

        if not self.csrftoken or not self.fb_dtsg or not self.lsd:
            log.error("Failed to extract all required tokens.")
            # log.debug(resp.text)

        if '%3A' in self.session_id:
            self.ds_user_id = self.session_id.split('%3A')[0]
        elif ':' in self.session_id:
            self.ds_user_id = self.session_id.split(':')[0]

        rev_patterns = [r'"server_revision":(\d+)', r'"client_revision":(\d+)', r'"revision":(\d+)']
        for pat in rev_patterns:
            m = re.search(pat, resp.text)
            if m:
                self.ajax_rev = m.group(1)
                break
        if not self.ajax_rev:
            self.ajax_rev = '1039855775'

        if self.fb_dtsg:
            self.jazoest = str(sum(ord(c) for c in self.fb_dtsg))
        else:
            self.jazoest = '26278'

        log.info(f'Session init | csrf={self.csrftoken} | dtsg={self.fb_dtsg} | lsd={self.lsd} | rev={self.ajax_rev} | uid={self.ds_user_id}')

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
            'X-FB-LSD': self.lsd,
            'Sec-Fetch-Dest': 'empty',
            'Sec-Fetch-Mode': 'cors',
            'Sec-Fetch-Site': 'same-origin',
        }
        if need_claim and self.www_claim:
            h['X-IG-WWW-Claim'] = self.www_claim
        return h

    def post(self, url: str, data: dict, need_claim: bool = False):
        if need_claim and not self.www_claim:
            self._fetch_www_claim_via_sso()
        
        headers = self.web_headers(need_claim)
        
        try:
            resp = self.s.post(url, headers=headers, data=data, proxies=self.proxy, timeout=15)
            resp.raise_for_status()
            return resp.json()
        except requests.RequestException as e:
            log.error(f"POST request to {url} failed: {e}")
            if 'resp' in locals():
                log.error(f"Response content: {resp.text}")
            return {}

    def _fetch_www_claim_via_sso(self):
        # Dummy implementation for now
        self.www_claim = '0'
        log.info("Faking www_claim for now.")

    def get_user_id(self, username: str) -> str:
        """Get user ID using GraphQL with HAR parameters."""
        log.info(f"Attempting to get user ID for {username}")
        
        variables = json.dumps({
            "id": username,
            "render_surface": "PROFILE", 
            "enable_integrity_filters": True
        })
        
        rand_seg = lambda: ''.join(random.choices('abcdefghijklmnopqrstuvwxyz0123456789', k=6))
        __s = f"{rand_seg()}:{rand_seg()}:{rand_seg()}"
        
        data = {
            'av': self.ds_user_id or '0',
            '__d': 'www',
            '__user': '0',
            '__a': '1',
            '__req': '1',
            '__hs': '20593.HYP:instagram_web_pkg.2.1...0',
            'dpr': '1',
            '__ccg': 'GOOD',
            '__rev': self.ajax_rev,
            '__s': __s,
            '__hsi': str(random.randint(7000000000000000000, 8000000000000000000)),
            '__dyn': '7xe5WwlEnwn8K2Wmh0no6u5U4e1ZyUW3qi2K360O81nEhw2nVE4W0qa0FE2awgo9o1vohwGwQwoEcE2ygao38woE2swlo8od8-U2zxe2GewGw9a361qw8W5U4q08OwLyES1Twoob82ZwrUdUbGwmk0KU6O1FwlA1HQp1yU426V89F8uwm8jw4kyVrx60jy7EG3a18whE981eUdoS',
            '__csr': '',
            '__hsdp': 'nMBi12pOWA2MSbARnPZ99devHcmWt2p2BJGEB0xwHucV48vAjAyEW6VSh2ElYM4C4S6j5Ao8msE4a9w9F3U5G1OAwCwTxa4UZ0AxS0-UK6EbUhwFwnEuGu3a2658S5Hwci5EeEC2i0O8Sdw9i3-fx60zoC5K1rx-05-Ukw19906Nw3RE560o-0dbwGw4Nw14O0h902go9oNAx209ww',
            '__hblp': '08G0PEW2u1CwcWEK2u1vK2y5SawnE8oeomAz8hDDwLyVE9U8onBwpE4u2a2CbxG2-4oaoqwgUpHGu3aEuxidBx2Vo4uq12wIxq3G9wAwdqdwoUW263KU-aCw8S9z8C15xuaxi1RwYwda0om08kwdG580SS1Mwbd0d60Co4m3l2U9rw3qoa8a824w9q1Og0QK2G0j6681Do1xE13EC0gx0ei1LweO7FENAx20ji0iK',
            '__sjsp': 'nMBi12pOWA2MSbARnRRQAAQUCIMCDgCgFrqG9g8oaTzeh27V4V8GexKtAgG5vc1toaA',
            '__comet_req': '7',
            'fb_dtsg': self.fb_dtsg,
            'jazoest': self.jazoest,
            'lsd': self.lsd,
            '__spin_r': self.ajax_rev,
            '__spin_b': 'trunk',
            '__spin_t': str(int(time.time())),
            '__crn': 'comet.igweb.PolarisFeedRoute',
            'fb_api_caller_class': 'RelayModern',
            'fb_api_req_friendly_name': 'PolarisProfilePageContentQuery',
            'server_timestamps': 'true',
            'variables': variables,
            'doc_id': '27937681195819736',
        }
        
        resp = self.post(IG_GRAPHQL_URL, data, need_claim=True)
        
        user_data = resp.get('data', {}).get('user', {})
        if user_data and ('id' in user_data or 'pk' in user_data):
            user_id = str(user_data.get('id', user_data.get('pk', '')))
            log.info(f"Successfully found user ID for {username}: {user_id}")
            return user_id
        
        log.error(f"Could not resolve user ID for {username}. Response: {resp}")
        return None

if __name__ == '__main__':
    try:
        with open('ses', 'r') as f:
            session_id = f.read().strip()
    except FileNotFoundError:
        log.error("'ses' file not found. Please create it with your sessionid.")
        exit()

    ig_session = IGWebSession(session_id=session_id)
    if ig_session.csrftoken and ig_session.fb_dtsg and ig_session.lsd:
        user_id = ig_session.get_user_id('60k5')
        if user_id:
            print(f"SUCCESS: User ID for 60k5 is {user_id}")
        else:
            print("FAILURE: Could not get user ID.")
    else:
        print("FAILURE: Could not initialize session properly.")
