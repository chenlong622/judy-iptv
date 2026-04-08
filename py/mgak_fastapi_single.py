from __future__ import annotations

import json
import time
from typing import Any, Dict, List, Optional, Tuple
from urllib.parse import urlparse

import requests
from fastapi import FastAPI, Query, Request
from fastapi.responses import HTMLResponse, JSONResponse, RedirectResponse, PlainTextResponse
import uvicorn

# ==================== 频道映射表（支持多线路）====================
CHANNEL_MAP: Dict[str, Dict[str, Any]] = {
    # 央视频道
    'cctv1': {'name': 'CCTV1综合', 'ids': [265183188, 265183189], 'no': 1},
    'cctv1b': {'name': 'CCTV1综合(备)', 'ids': [265183188, 265183669], 'no': 1},
    'cctv2': {'name': 'CCTV2财经', 'ids': [265667329, 265667330], 'no': 2},
    'cctv3': {'name': 'CCTV3综艺', 'ids': [265667206, 265667207], 'no': 3},
    'cctv4': {'name': 'CCTV4中文国际', 'ids': [265667639, 265667640], 'no': 4},
    'cctv4o': {'name': 'CCTV4欧洲', 'ids': [265667313, 265667314], 'no': 4},
    'cctv4a': {'name': 'CCTV4美洲', 'ids': [265667335, 265667336], 'no': 4},
    'cctv5': {'name': 'CCTV5体育', 'ids': [265667565, 265667566], 'no': 5},
    'cctv5p': {'name': 'CCTV5+体育赛事', 'ids': [265106763, 265125883], 'no': 16},
    'cctv5p2': {'name': 'CCTV5+体育赛事2', 'ids': [265106763, 265106764], 'no': 16},
    'cctv6': {'name': 'CCTV6电影', 'ids': [265667482, 265667483], 'no': 6},
    'cctv7': {'name': 'CCTV7国防军事', 'ids': [265667268, 265667269], 'no': 7},
    'cctv8': {'name': 'CCTV8电视剧', 'ids': [265667466, 265667467], 'no': 8},
    'cctv9': {'name': 'CCTV9纪录', 'ids': [265667202, 265667203], 'no': 9},
    'cctv10': {'name': 'CCTV10科教', 'ids': [265667631, 265667632], 'no': 10},
    'cctv11': {'name': 'CCTV11戏曲', 'ids': [265667429, 265667430], 'no': 11},
    'cctv12': {'name': 'CCTV12社会与法', 'ids': [265667607, 265667608], 'no': 12},
    'cctv13': {'name': 'CCTV13新闻', 'ids': [1139280199, 1139280200], 'no': 13},
    'cctv14': {'name': 'CCTV14少儿', 'ids': [265667325, 265667326], 'no': 14},
    'cctv15': {'name': 'CCTV15音乐', 'ids': [265667535, 265667536], 'no': 15},
    'cctv17': {'name': 'CCTV17农业农村', 'ids': [265667526, 265667527], 'no': 17},
    'cctv9doc': {'name': 'CCTV9 Documentary', 'ids': [265218920, 265218922], 'no': None},
    'cgtna': {'name': 'CGTN阿拉伯语', 'ids': [265219154, 265219155], 'no': None},
    'cgtne': {'name': 'CGTN西班牙语', 'ids': [265218872, 265218873], 'no': None},
    'cctvf': {'name': 'CCTV法语', 'ids': [265219025, 265219026], 'no': None},
    'cctvr': {'name': 'CCTV俄语', 'ids': [265218806, 265218807], 'no': None},
    'lgs': {'name': 'CCTV老故事', 'ids': [810326846, 810326847], 'no': None},
    'fxzl': {'name': 'CCTV发现之旅', 'ids': [810326624, 810326625], 'no': None},
    'zxs': {'name': 'CCTV中学生', 'ids': [810326679, 810326680], 'no': None},

    # 卫视频道
    'dfws': {'name': '东方卫视', 'ids': [1098710943, 1098710944], 'no': 28},
    'jsws': {'name': '江苏卫视', 'ids': [264104188, 264104189], 'no': 32},
    'gdws': {'name': '广东卫视', 'ids': [263541274, 275480030], 'no': 31},
    'jxws': {'name': '江西卫视', 'ids': [810783159, 810783160], 'no': None},
    'hnws': {'name': '河南卫视', 'ids': [1008007050, 1008007051], 'no': None},
    'sxws': {'name': '陕西卫视', 'ids': [816409120, 816409121], 'no': None},
    'dwqws': {'name': '大湾区卫视', 'ids': [265218882, 265218883], 'no': None},
    'hubws': {'name': '湖北卫视', 'ids': [1066830679, 1066830680], 'no': None},
    'jlws': {'name': '吉林卫视', 'ids': [1066865348, 1066865349], 'no': None},
    'qhws': {'name': '青海卫视', 'ids': [1066885177, 1066885178], 'no': None},
    'dnws': {'name': '东南卫视', 'ids': [810326620, 810454855], 'no': None},
    'hinws': {'name': '海南卫视', 'ids': [1066884988, 1066884989], 'no': None},
    'hxws': {'name': '海峡卫视', 'ids': [810326850, 810455033], 'no': None},

    # 数字/特色频道
    'yxfy': {'name': '游戏风云', 'ids': [265667664, 265667665], 'no': None},
    'sszjd': {'name': '赛事最经典', 'ids': [265218921, 265218922], 'no': None},
    'ttmlh': {'name': '体坛名栏汇', 'ids': [265218759, 265218760], 'no': None},
    'shdy': {'name': '四海钓鱼', 'ids': [265667494, 265667495], 'no': None},
    'xpfy': {'name': '新片放映厅', 'ids': [265218930, 265218931], 'no': None},
    'zjsv': {'name': '追剧少女', 'ids': [265218878, 265218879], 'no': None},
    'chcjtyy': {'name': 'CHC家庭影院', 'ids': [265667645, 265667646], 'no': None},
    'chcdzdy': {'name': 'CHC动作电影', 'ids': [265218967, 265218968], 'no': None},
    'rbj': {'name': '热剧联播', 'ids': [265218955, 265218956], 'no': None},
    'gqdp': {'name': '高清大片', 'ids': [265218862, 265218863], 'no': None},
    'mgysdy': {'name': '咪咕云上电影院', 'ids': [265219029, 265219030], 'no': None},
    'jsjy': {'name': '江苏教育', 'ids': [265219146, 265219147], 'no': None},
    'sdjy': {'name': '山东教育', 'ids': [265218942, 265218943], 'no': None},

    # 熊猫频道
    'xmpt': {'name': '熊猫频道', 'ids': [265667599, 265667600], 'no': None},
    'xmpt1': {'name': '熊猫频道1', 'ids': [265219065, 265219066], 'no': None},
    'xmpt2': {'name': '熊猫频道2', 'ids': [265218959, 265218960], 'no': None},
    'xmpt3': {'name': '熊猫频道3', 'ids': [265218910, 265218911], 'no': None},
    'xmpt4': {'name': '熊猫频道4', 'ids': [265218991, 265218992], 'no': None},
    'xmpt6': {'name': '熊猫频道6', 'ids': [265218934, 265218935], 'no': None},
    'xmpt7': {'name': '熊猫频道7', 'ids': [265219037, 265219038], 'no': None},
    'xmpt8': {'name': '熊猫频道8', 'ids': [265218971, 265218972], 'no': None},
    'xmpt9': {'name': '熊猫频道9', 'ids': [265218886, 265218887], 'no': None},
    'xmpt10': {'name': '熊猫频道10', 'ids': [265218794, 265218795], 'no': None},
}

# ==================== 配置常量 ====================
DEFAULT_UA = 'Dalvik/2.1.0 (Linux; U; Android 15; XIAOMI-15 Build/TP1A.220624.014)'
DEFAULT_EDS_LOGIN_URL = 'http://aikanlive.miguvideo.com:8082/EDS/JSON/Login'
DEFAULT_GETTIME_URL = 'http://aikanvod.miguvideo.com/video/p/getTime.jsp?vt=9'
DEFAULT_BUSINESS_TYPE = 'BTV'
LOGIN_STATE_CACHE_KEY = 'migu:login_state'
LOGIN_STATE_TTL = 1200
PLAYURL_CACHE_PREFIX = 'migu:playurl:'
PLAYURL_TTL = 600
AUTH_EXPIRED_CODES = {
    '-2', '125023001', '125023002', '125023003', '125023004',
    '125023005', '125023006', '125023007', '125023008', '125023009',
    '125023010', '125023011', '125023012',
}


class TTLCache:
    def __init__(self) -> None:
        self._data: Dict[str, Tuple[Any, float]] = {}

    def get(self, key: str) -> Any:
        item = self._data.get(key)
        if not item:
            return None
        value, expires_at = item
        if expires_at < time.time():
            self._data.pop(key, None)
            return None
        return value

    def set(self, key: str, value: Any, ttl: int) -> None:
        self._data[key] = (value, time.time() + ttl)


cache = TTLCache()
app = FastAPI(title='咪咕直播统一入口（FastAPI 单文件版）')
session = requests.Session()


def respond_json(payload: Dict[str, Any], status: int = 200) -> JSONResponse:
    return JSONResponse(content=payload, status_code=status)


def normalize_cookie_pair(raw_set_cookie: str) -> str:
    if not raw_set_cookie:
        return ''
    return raw_set_cookie.split(';', 1)[0].strip()


def pick_ret_code(data: Dict[str, Any]) -> str:
    for k in ('retCode', 'retcode', 'realStrRetCode'):
        value = data.get(k)
        if isinstance(value, str) and value:
            return value
    result = data.get('result')
    if isinstance(result, dict):
        for k in ('retCode', 'retcode'):
            value = result.get(k)
            if isinstance(value, str) and value:
                return value
    return ''


def pick_ret_msg(data: Dict[str, Any]) -> str:
    for k in ('retMsg', 'retmsg', 'message', 'msg'):
        value = data.get(k)
        if isinstance(value, str) and value:
            return value
    result = data.get('result')
    if isinstance(result, dict):
        for k in ('retMsg', 'retmsg', 'message', 'msg'):
            value = result.get(k)
            if isinstance(value, str) and value:
                return value
    return ''


def need_relogin(status_code: int, ret_code: str, ret_msg: str) -> bool:
    if status_code in (401, 403):
        return True
    if ret_code in AUTH_EXPIRED_CODES:
        return True
    lower = ret_msg.lower()
    return any(hint in lower for hint in ('session', 'login', 'authenticate', 'expired', 'epgsession'))


def plus_one_numeric_string(n: str) -> str:
    if not n.isdigit():
        raise RuntimeError(f'channelID 必须是纯数字字符串，当前值: {n}')
    return str(int(n) + 1)


def http_request(method: str, url: str, headers: Dict[str, str], body: Optional[str], timeout: int = 10) -> Dict[str, Any]:
    try:
        response = session.request(
            method=method,
            url=url,
            headers=headers,
            data=body,
            timeout=timeout,
            allow_redirects=False,
        )
    except requests.RequestException as exc:
        return {'ok': False, 'error': f'request 失败: {exc}'}

    set_cookies: List[str] = []
    try:
        raw_headers = response.raw.headers
        set_cookies = raw_headers.get_all('Set-Cookie') or []
    except Exception:
        one = response.headers.get('Set-Cookie')
        if one:
            set_cookies = [one]

    return {
        'ok': True,
        'status': response.status_code,
        'body': response.text,
        'headers': {k.lower(): v for k, v in response.headers.items()},
        'set_cookies': set_cookies,
    }


def post_json_follow_302_once(url: str, payload: Dict[str, Any], headers: Dict[str, str], timeout: int = 10) -> Dict[str, Any]:
    body = json.dumps(payload, ensure_ascii=False)
    resp = http_request('POST', url, headers, body, timeout)
    if not resp['ok']:
        return resp
    if int(resp['status']) == 302 and resp['headers'].get('location'):
        redirected = str(resp['headers']['location'])
        h2 = dict(headers)
        h2.pop('isEncrypt', None)
        resp = http_request('POST', redirected, h2, body, timeout)
    return resp


def find_cookie_raw(set_cookies: List[str], keyword: str) -> str:
    for line in set_cookies:
        if keyword in line:
            return line
    return ''


def build_cookie(state: Dict[str, Any], include_arrayid: bool = True) -> str:
    parts = [f"JSESSIONID={state.get('session_id', '')}"]
    if state.get('set_cookie_raw'):
        pair = normalize_cookie_pair(str(state['set_cookie_raw']))
        if pair:
            parts.append(pair)
    if include_arrayid and state.get('arrayid_raw'):
        pair = normalize_cookie_pair(str(state['arrayid_raw']))
        if pair:
            parts.append(pair)
    return '; '.join(parts)


def login_eds(state: Dict[str, Any], phone: str, timeout: int) -> None:
    payload: Dict[str, Any] = {}
    if phone.isdigit() and len(phone) == 11:
        payload['UserID'] = phone

    headers = {
        'User-Agent': DEFAULT_UA,
        'Content-Type': 'application/json; charset=UTF-8',
        'Accept': '*/*',
        'Connection': 'keep-alive',
        'isEncrypt': '0',
    }
    resp = post_json_follow_302_once(DEFAULT_EDS_LOGIN_URL, payload, headers, timeout)
    if not resp['ok']:
        raise RuntimeError(resp['error'])
    if not (200 <= int(resp['status']) < 300):
        raise RuntimeError(f"EDS 登录失败: HTTP {resp['status']}")

    try:
        data = json.loads(str(resp['body']))
    except Exception as exc:
        raise RuntimeError(f'EDS 返回非 JSON: {exc}') from exc

    base_url = str(data.get('epgurl', '')).rstrip('/')
    if not base_url:
        raise RuntimeError('EDS 未返回 epgurl')

    state['base_url'] = base_url
    state['login_url'] = str(data.get('epghttpsurl') or base_url).rstrip('/')
    state['set_cookie_raw'] = find_cookie_raw(resp.get('set_cookies', []), 'premsisdn')


def authenticate(state: Dict[str, Any], timeout: int) -> None:
    base_url = str(state.get('base_url', ''))
    if not base_url:
        raise RuntimeError('base_url 为空，请先调用 login_eds')

    payload = {
        'areaID': '1',
        'locale': '1',
        'loginType': '3',
        'OSVersion': '13',
        'physicalDeviceID': '000000000000000',
        'templatelame': 'default',
        'terminalType': 'AndroidPhone',
        'terminalVendor': 'XiaoMi',
        'timeZone': '+0800',
        'userGroup': '100',
        'softwareVersion': '581$0$XM-15',
        'channelInfo': '00990103',
    }
    headers = {
        'User-Agent': DEFAULT_UA,
        'Content-Type': 'application/json; charset=UTF-8',
        'Accept': '*/*',
        'Connection': 'keep-alive',
        'isEncrypt': '0',
    }

    url = f'{base_url}/EPG/VPE/PHONE/Authenticate'
    body = json.dumps(payload, ensure_ascii=False)
    resp = http_request('POST', url, headers, body, timeout)
    if not resp['ok']:
        raise RuntimeError(resp['error'])
    if not (200 <= int(resp['status']) < 300):
        raise RuntimeError(f"Authenticate 失败: HTTP {resp['status']}")

    try:
        data = json.loads(str(resp['body']))
    except Exception as exc:
        raise RuntimeError(f'Authenticate 返回非 JSON: {exc}') from exc

    ret_code = pick_ret_code(data)
    if ret_code not in ('', '0', '000000000'):
        raise RuntimeError(f'Authenticate retCode={ret_code}')

    session_id = ''
    for candidate in (
        data.get('sessionID'),
        data.get('sessionid'),
        (data.get('result') or {}).get('sessionID') if isinstance(data.get('result'), dict) else None,
        (data.get('result') or {}).get('sessionid') if isinstance(data.get('result'), dict) else None,
    ):
        if isinstance(candidate, str) and candidate.strip():
            session_id = candidate.strip()
            break

    if not session_id:
        raise RuntimeError('未拿到 sessionID/sessionid')
    state['session_id'] = session_id


def refresh_arrayid(state: Dict[str, Any], timeout: int) -> None:
    headers = {
        'User-Agent': DEFAULT_UA,
        'Accept': '*/*',
        'Connection': 'keep-alive',
        'EpgSession': f"JSESSIONID={state.get('session_id', '')}",
        'Location': str(state.get('base_url', '')),
        'Cookie': build_cookie(state, include_arrayid=False),
    }
    resp = http_request('GET', DEFAULT_GETTIME_URL, headers, None, timeout)
    if not resp['ok']:
        raise RuntimeError(resp['error'])
    arr = find_cookie_raw(resp.get('set_cookies', []), 'arrayid')
    if arr:
        state['arrayid_raw'] = arr


def run_login_flow(phone: str, timeout: int) -> Dict[str, Any]:
    state: Dict[str, Any] = {
        'base_url': '',
        'login_url': '',
        'session_id': '',
        'set_cookie_raw': '',
        'arrayid_raw': '',
    }
    login_eds(state, phone, timeout)
    authenticate(state, timeout)
    refresh_arrayid(state, timeout)
    return state


def play_channel(state: Dict[str, Any], business_type: str, channel_id: str, media_id: str, timeout: int) -> Dict[str, Any]:
    base_url = str(state.get('base_url', ''))
    if not base_url:
        raise RuntimeError('base_url 为空')

    parsed = urlparse(base_url)
    if not parsed.hostname:
        raise RuntimeError(f'base_url 解析失败: {base_url}')
    host = parsed.hostname if not parsed.port else f'{parsed.hostname}:{parsed.port}'

    body_arr = {
        'IDType': 0,
        'businessType': business_type,
        'channelID': channel_id,
        'mediaID': media_id,
    }
    body = json.dumps(body_arr, ensure_ascii=False)

    headers = {
        'User-Agent': DEFAULT_UA,
        'isEncrypt': '0',
        'EpgSession': f"JSESSIONID={state.get('session_id', '')}",
        'Location': base_url,
        'Cookie': build_cookie(state, include_arrayid=True),
        'Content-Type': 'application/json; charset=UTF-8',
        'Accept': '*/*',
        'Host': host,
        'Connection': 'keep-alive',
    }
    url = f'{base_url}/VSP/V3/PlayChannel'
    resp = http_request('POST', url, headers, body, timeout)
    if not resp['ok']:
        raise RuntimeError(resp['error'])
    try:
        data = json.loads(str(resp['body']))
        if not isinstance(data, dict):
            data = {}
    except Exception:
        data = {}
    return {'status': int(resp['status']), 'data': data, 'raw_body': str(resp['body'])}


def fetch_login_state(force: bool, phone: str, timeout: int, debug_log: List[str]) -> Dict[str, Any]:
    if not force:
        cached = cache.get(LOGIN_STATE_CACHE_KEY)
        if isinstance(cached, dict) and cached.get('base_url') and cached.get('session_id'):
            debug_log.append('[cache] 命中登录态缓存')
            return cached

    debug_log.append('[login] 重新登录并刷新登录态缓存')
    state = run_login_flow(phone, timeout)
    cache.set(LOGIN_STATE_CACHE_KEY, state, LOGIN_STATE_TTL)
    return state


def get_play_url_with_fallback(channel_ids: List[int], business_type: str, phone: str, force: bool, timeout: int, debug_log: List[str]) -> Dict[str, Any]:
    last_error: Optional[str] = None

    for index, channel_id in enumerate(channel_ids):
        line_num = index + 1
        debug_log.append(f'[line{line_num}] 尝试线路，频道ID: {channel_id}')

        try:
            play_cache_key = f'{PLAYURL_CACHE_PREFIX}{channel_id}'
            cached_play_url = cache.get(play_cache_key)
            if isinstance(cached_play_url, str) and cached_play_url:
                debug_log.append(f'[line{line_num}] 命中缓存')
                return {'playURL': cached_play_url, 'channelId': channel_id, 'line': line_num, 'source': 'cache'}

            state = fetch_login_state(force, phone, timeout, debug_log)
            mid = plus_one_numeric_string(str(channel_id))
            play_resp = play_channel(state, business_type, str(channel_id), mid, timeout)
            ret_code = pick_ret_code(play_resp['data'])
            ret_msg = pick_ret_msg(play_resp['data'])

            if need_relogin(int(play_resp['status']), ret_code, ret_msg):
                debug_log.append(f'[line{line_num}] 会话失效，重新登录')
                state = run_login_flow(phone, timeout)
                cache.set(LOGIN_STATE_CACHE_KEY, state, LOGIN_STATE_TTL)
                play_resp = play_channel(state, business_type, str(channel_id), mid, timeout)
                ret_code = pick_ret_code(play_resp['data'])
                ret_msg = pick_ret_msg(play_resp['data'])

            data = play_resp['data']
            play_url = str(data.get('playURL', '')).strip() if isinstance(data, dict) else ''
            if play_url:
                cache.set(play_cache_key, play_url, PLAYURL_TTL)
                debug_log.append(f'[line{line_num}] 成功获取播放地址')
                return {'playURL': play_url, 'channelId': channel_id, 'line': line_num, 'source': 'api'}

            debug_log.append(f'[line{line_num}] 返回空地址，retCode: {ret_code}, retMsg: {ret_msg}')
            last_error = f'线路{line_num}返回空地址: {ret_msg}'
        except Exception as exc:
            debug_log.append(f'[line{line_num}] 异常: {exc}')
            last_error = f'线路{line_num}异常: {exc}'

    raise RuntimeError(f'所有线路均失败，最后错误: {last_error}')


def render_channel_list_html(channels: Dict[str, Dict[str, Any]]) -> str:
    categories = {
        'cctv': {'name': '📺 央视频道', 'keys': ['cctv1','cctv2','cctv3','cctv4','cctv5','cctv5p','cctv6','cctv7','cctv8','cctv9','cctv10','cctv11','cctv12','cctv13','cctv14','cctv15','cctv17','cgtna','cgtne','cctvf','cctvr']},
        'weishi': {'name': '⭐ 卫视频道', 'keys': ['dfws','jsws','gdws','jxws','hnws','sxws','dwqws','hubws','jlws','qhws','dnws','hinws','hxws']},
        'digital': {'name': '🎬 数字频道', 'keys': ['yxfy','sszjd','ttmlh','shdy','xpfy','zjsv','chcjtyy','chcdzdy','rbj','gqdp','mgysdy']},
        'panda': {'name': '🐼 熊猫频道', 'keys': ['xmpt','xmpt1','xmpt2','xmpt3','xmpt4','xmpt6','xmpt7','xmpt8','xmpt9','xmpt10']},
    }

    html = ['<div class="categories">']
    for cat in categories.values():
        html.append(f'<div class="category"><h3>{cat["name"]}</h3><div class="channel-grid">')
        for key in cat['keys']:
            ch = channels.get(key)
            if not ch:
                continue
            channel_no = f'[{ch["no"]}]' if ch.get('no') is not None else ''
            html.append(
                f'''<a href="/?id={key}" class="channel-card" data-key="{key}">
                    <div class="channel-no">{channel_no}</div>
                    <div class="channel-name">{ch["name"]}</div>
                    <div class="channel-lines">{len(ch["ids"])}线路</div>
                </a>'''
            )
        html.append('</div></div>')
    html.append('</div>')
    return ''.join(html)


@app.get('/', response_class=HTMLResponse)
def main(
    request: Request,
    action: str = Query('', alias='action'),
    id: str = Query('cctv1', alias='id'),
    line: int = Query(0, alias='line'),
    json_mode: int = Query(0, alias='json'),
    debug: int = Query(0, alias='debug'),
    list_mode: Optional[str] = Query(None, alias='list'),
    q: Optional[str] = Query(None, alias='q'),
    force: int = Query(0, alias='force'),
    phone: str = Query('', alias='phone'),
):
    # 显示频道列表
    if list_mode is not None or action == 'list':
        html = f'''<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>咪咕直播 - 频道列表（多线路）</title>
    <style>
        * {{ margin: 0; padding: 0; box-sizing: border-box; }}
        body {{ font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; background: linear-gradient(135deg, #1a1a2e 0%, #16213e 100%); min-height: 100vh; padding: 20px; }}
        .container {{ max-width: 1400px; margin: 0 auto; }}
        .header {{ background: rgba(255,255,255,0.1); backdrop-filter: blur(10px); border-radius: 20px; padding: 20px; margin-bottom: 20px; text-align: center; }}
        h1 {{ color: #fff; margin-bottom: 10px; }}
        .subtitle {{ color: #aaa; }}
        .search-box {{ width: 100%; max-width: 400px; margin: 20px auto 0; padding: 12px 20px; font-size: 16px; border: none; border-radius: 50px; background: rgba(255,255,255,0.2); color: white; outline: none; }}
        .search-box::placeholder {{ color: rgba(255,255,255,0.6); }}
        .categories {{ display: flex; flex-direction: column; gap: 20px; }}
        .category {{ background: rgba(255,255,255,0.05); border-radius: 20px; padding: 20px; backdrop-filter: blur(5px); }}
        .category h3 {{ color: #ff6b6b; margin-bottom: 15px; font-size: 20px; }}
        .channel-grid {{ display: grid; grid-template-columns: repeat(auto-fill, minmax(130px, 1fr)); gap: 12px; }}
        .channel-card {{ display: block; background: rgba(255,255,255,0.1); border-radius: 12px; padding: 12px; text-align: center; text-decoration: none; transition: all 0.3s; position: relative; }}
        .channel-card:hover {{ background: #ff6b6b; transform: translateY(-3px); }}
        .channel-no {{ color: #ff6b6b; font-size: 11px; margin-bottom: 5px; }}
        .channel-name {{ color: white; font-size: 13px; font-weight: 500; }}
        .channel-lines {{ color: rgba(255,255,255,0.5); font-size: 10px; margin-top: 5px; }}
        .channel-card:hover .channel-no {{ color: white; }}
        .player-container {{ position: fixed; bottom: 0; left: 0; right: 0; background: #000; z-index: 1000; transform: translateY(100%); transition: transform 0.3s; }}
        .player-container.active {{ transform: translateY(0); }}
        .player-header {{ display: flex; justify-content: space-between; align-items: center; padding: 10px 20px; background: rgba(0,0,0,0.9); color: white; }}
        .line-info {{ font-size: 12px; color: #ff6b6b; }}
        .close-player {{ background: #dc3545; border: none; color: white; padding: 5px 15px; border-radius: 5px; cursor: pointer; }}
        .video-wrapper {{ position: relative; padding-bottom: 56.25%; height: 0; }}
        #videoPlayer {{ position: absolute; top: 0; left: 0; width: 100%; height: 100%; }}
        @media (max-width: 768px) {{ .channel-grid {{ grid-template-columns: repeat(auto-fill, minmax(100px, 1fr)); }} }}
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>📺 咪咕直播（多线路自动切换）</h1>
            <p class="subtitle">点击频道开始观看 | 支持多线路自动故障转移</p>
            <input type="text" class="search-box" id="searchInput" placeholder="搜索频道...">
        </div>
        <div id="channelList">{render_channel_list_html(CHANNEL_MAP)}</div>
    </div>
    <div class="player-container" id="playerContainer">
        <div class="player-header">
            <span id="currentChannel">正在播放...</span>
            <span id="lineInfo" class="line-info"></span>
            <button class="close-player" onclick="closePlayer()">关闭</button>
        </div>
        <div class="video-wrapper">
            <video id="videoPlayer" controls autoplay></video>
        </div>
    </div>
    <script src="https://cdn.jsdelivr.net/npm/hls.js@latest"></script>
    <script>
        function searchChannel() {{
            const keyword = document.getElementById("searchInput").value.toLowerCase();
            document.querySelectorAll(".channel-card").forEach(card => {{
                card.style.display = card.textContent.toLowerCase().includes(keyword) ? "block" : "none";
            }});
        }}
        document.getElementById("searchInput").addEventListener("input", searchChannel);
        async function playChannel(channelKey) {{
            const container = document.getElementById("playerContainer");
            const video = document.getElementById("videoPlayer");
            const currentSpan = document.getElementById("currentChannel");
            const lineInfo = document.getElementById("lineInfo");
            container.classList.add("active");
            currentSpan.textContent = "加载中...";
            lineInfo.textContent = "";
            const response = await fetch(`/?id=${{channelKey}}&json=1`);
            const data = await response.json();
            if (data.ok && data.playURL) {{
                currentSpan.textContent = data.channelName || channelKey;
                lineInfo.textContent = `线路${{data.line}} (${{data.source}})`;
                if (Hls.isSupported()) {{
                    const hls = new Hls();
                    hls.loadSource(data.playURL);
                    hls.attachMedia(video);
                }} else if (video.canPlayType("application/vnd.apple.mpegurl")) {{
                    video.src = data.playURL;
                }} else {{
                    alert("您的浏览器不支持HLS播放");
                }}
            }} else {{
                alert("获取播放地址失败: " + (data.error || "未知错误"));
            }}
        }}
        function closePlayer() {{
            const container = document.getElementById("playerContainer");
            const video = document.getElementById("videoPlayer");
            container.classList.remove("active");
            video.pause();
            video.src = "";
        }}
        document.querySelectorAll(".channel-card").forEach(card => {{
            card.addEventListener("click", function(e) {{
                e.preventDefault();
                playChannel(this.dataset.key);
            }});
        }});
    </script>
</body>
</html>'''
        return HTMLResponse(content=html)

    # 搜索频道
    if action == 'search' and q is not None:
        keyword = q.strip().lower()
        results = []
        for key, ch in CHANNEL_MAP.items():
            if keyword in ch['name'].lower() or keyword in key.lower():
                results.append({'key': key, 'ids': ch['ids'], 'name': ch['name'], 'no': ch['no']})
        return respond_json({'ok': True, 'results': results})

    # 获取频道信息
    if id not in CHANNEL_MAP:
        found = None
        for key, ch in CHANNEL_MAP.items():
            if any(str(id) == str(cid) for cid in ch['ids']):
                found = key
                break
        if found:
            id = found
        else:
            return respond_json({'ok': False, 'error': f'未知频道: {id}'}, 400)

    channel = CHANNEL_MAP[id]
    channel_name = channel['name']
    channel_ids = list(channel['ids'])

    if line > 0 and line <= len(channel_ids):
        channel_ids = [channel_ids[line - 1]]

    business_type = DEFAULT_BUSINESS_TYPE
    timeout = 10
    debug_log: List[str] = []

    try:
        result = get_play_url_with_fallback(channel_ids, business_type, phone, force == 1, timeout, debug_log)
        if json_mode != 1:
            return RedirectResponse(url=result['playURL'], status_code=302)

        return respond_json({
            'ok': True,
            'source': result['source'],
            'channelId': result['channelId'],
            'channelName': channel_name,
            'line': result['line'],
            'totalLines': len(channel['ids']),
            'playURL': result['playURL'],
            'debug': debug_log if debug == 1 else None,
        }, 200)
    except Exception as exc:
        return respond_json({
            'ok': False,
            'error': str(exc),
            'channelName': channel_name,
            'totalLines': len(channel['ids']),
            'debug': debug_log if debug == 1 else None,
        }, 500)


@app.get('/healthz', response_class=PlainTextResponse)
def healthz() -> str:
    return 'ok'


if __name__ == '__main__':
    uvicorn.run('mgak_fastapi_single:app', host='0.0.0.0', port=8000, reload=False)
