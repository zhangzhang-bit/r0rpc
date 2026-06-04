import json

import requests


BASE_URL = 'http://159.75.100.225:9876'
ADMIN_USER = 'admin'
ADMIN_PASS = '123456'


def invoke_yeemiao_get_sign():
    pdata = {
        'mobile': '15555555555',
        'token': '',
        'type': 5,
    }
    param = json.dumps(pdata, separators=(',', ':'), ensure_ascii=False)

    url = f'{BASE_URL}/rpc/invoke/yeemiao/get_sign'
    body = {
        'username': ADMIN_USER,
        'password': ADMIN_PASS,
        'timeoutSeconds': 20,
        'payload': {
            'param': param,
        },
    }

    response = requests.post(url, json=body, timeout=25)
    response.raise_for_status()
    return response.json()


if __name__ == '__main__':
    print(json.dumps(invoke_yeemiao_get_sign(), ensure_ascii=False, indent=2))
