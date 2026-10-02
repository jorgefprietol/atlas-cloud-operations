"""Generate local credentials without printing or overwriting an existing file."""
from pathlib import Path
import secrets

root = Path(__file__).resolve().parents[1]
target = root / '.env'
if target.exists():
    print('.env already exists; retained existing configuration.')
else:
    with target.open('x', encoding='utf-8', newline='\n') as file:
        file.write(f'DB_PASSWORD={secrets.token_hex(24)}\nDEV_API_TOKEN={secrets.token_hex(32)}\n')
    print('Created .env with random local credentials. Do not commit this file.')
