import requests

sekiro_url = "http://159.75.100.225:5602/invoke"
data = {
    "group": "idlefish",
    "action": "decrypt",
    'encode_str': 'v7eNwdELBmc1hOkagpP6NQ==',
}


resp = requests.post(sekiro_url, data=data)
print(resp.json())