import requests

BASE_URL = 'http://159.75.100.225:9876'
ADMIN_USER = 'admin'
ADMIN_PASS = '123456'


def query_seller_id(seller_id):
    body = {
        'username': ADMIN_USER,
        'password': ADMIN_PASS,
        'timeoutSeconds': 1,
        'payload': {
            'encode_str': seller_id,
        },
    }

    url = f'{BASE_URL}/rpc/invoke/idlefish/decrypt'
    response = requests.post(url, json=body, timeout=5)
    response.raise_for_status()
    print(response.text)


for _ in range(100):
    query_seller_id('v7eNwdELBmc1hOkagpP6NQ==')
