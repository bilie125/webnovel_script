#!/bin/bash

# Переменные
BOT_DIR="/home/ubuntu/telegram_bot"   # Путь к директории бота
VENV_DIR="$BOT_DIR/venv"
SCRIPT_NAME="your_script.py"  # Замените на имя вашего Python-скрипта
SERVICE_FILE="/etc/systemd/system/telegram_bot.service"

# Проверка, существует ли директория, если нет, то создать
if [ ! -d "$BOT_DIR" ]; then
    sudo mkdir -p $BOT_DIR
    sudo chown $USER:$USER $BOT_DIR
fi

# Переход в директорию бота
cd $BOT_DIR

# Создание виртуального окружения и установка зависимостей
python3 -m venv venv
source $VENV_DIR/bin/activate
pip install aiogram aiohttp beautifulsoup4

# Сохранение кода бота в файл
cat <<EOF > $SCRIPT_NAME
import logging
import asyncio
from aiogram import Bot, Dispatcher, types
from aiogram.filters import Command, CommandStart
from aiogram.types import Message
from bs4 import BeautifulSoup
import aiohttp
import re

API_TOKEN = 'token'
GROUP_CHAT_ID = '-1002079142065'  # Замените на ID вашей группы
CHAT_ID = '6273910889'
URL_WEBNOVEL = 'https://webnovel.com/book/shadow-slave_22196546206090805/catalog'
URL_BOOSTY = 'https://boosty.to/shadow_slave'

# Инициализация бота и диспетчера
bot = Bot(token=API_TOKEN)
dp = Dispatcher()

# В памяти храним последние две главы
last_chapters_webnovel = []
sent_chapters_boosty = []

# Включение логирования
logging.basicConfig(level=logging.INFO)

async def fetch_webnovel_chapter():
    headers = {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36'
    }
    try:
        async with aiohttp.ClientSession() as session:
            async with session.get(URL_WEBNOVEL, headers=headers) as response:
                if response.status == 200:
                    html = await response.text()
                    soup = BeautifulSoup(html, 'html.parser')
                    chapter_tag = soup.find('a', class_='ell lst-chapter dib vam')
                    return chapter_tag.text.strip() if chapter_tag else None
                else:
                    logging.error(f'Ошибка при запросе страницы Webnovel: {response.status}')
                    return None
    except Exception as e:
        logging.error(f'Ошибка при запросе Webnovel: {e}')
        return None

async def fetch_boosty_chapters():
    try:
        async with aiohttp.ClientSession() as session:
            async with session.get(URL_BOOSTY) as response:
                if response.status == 200:
                    html = await response.text()
                    soup = BeautifulSoup(html, 'html.parser')
                    chapters = soup.find_all('div', class_='PostSubscriptionBlock_title_WXCN0')
                    filtered_chapters = [
                        chapter.get_text(strip=True)
                        for chapter in chapters
                        if re.match(r'^Глава \d+: .+$', chapter.get_text(strip=True))
                    ][:2]
                    return filtered_chapters
                else:
                    logging.error(f'Ошибка при запросе страницы Boosty: {response.status}')
                    return []
    except Exception as e:
        logging.error(f'Ошибка при запросе Boosty: {e}')
        return []

async def check_new_chapters():
    latest_chapter_webnovel = await fetch_webnovel_chapter()
    new_chapters_found = False

    if latest_chapter_webnovel and (not last_chapters_webnovel or latest_chapter_webnovel != last_chapters_webnovel[-1]):
        last_chapters_webnovel.append(latest_chapter_webnovel)
        if len(last_chapters_webnovel) > 2:
            last_chapters_webnovel.pop(0)
        await bot.send_message(GROUP_CHAT_ID, f"Вышла новая глава на Webnovel: {latest_chapter_webnovel}")
        new_chapters_found = True

    boosty_chapters = await fetch_boosty_chapters()
    new_chapters = [chapter for chapter in boosty_chapters if chapter not in sent_chapters_boosty]
    if new_chapters:
        sent_chapters_boosty.extend(new_chapters)
        for chapter in reversed(new_chapters):
            await bot.send_message(CHAT_ID, chapter)
        new_chapters_found = True

    return new_chapters_found

async def check_updates():
    while True:
        try:
            logging.info("Периодическая проверка новых глав...")
            new_chapters_found = await check_new_chapters()
            if not new_chapters_found:
                logging.info("Новых глав не найдено.")
        except Exception as e:
            logging.error(f"Ошибка при периодической проверке: {e}")
        await asyncio.sleep(30)  # Опрос каждые 30 секунд

@dp.message(CommandStart())
async def send_welcome(message: types.Message):
    await message.reply("Привет! Я бот, который уведомляет о новых главах на Webnovel и Boosty.")

@dp.message(Command("last"))
async def last_chapter(message: types.Message):
    webnovel_chapters = "\n".join(last_chapters_webnovel)
    boosty_chapters = "\n".join(reversed(sent_chapters_boosty[-2:]))
    
    response = (
        f"<b>Новые главы на <a href='{URL_WEBNOVEL}'>Webnovel</a>:</b>\n{webnovel_chapters}\n\n"
        f"<b>Новые главы на <a href='{URL_BOOSTY}'>Boosty</a>:</b>\n{boosty_chapters}"
    )
    
    await message.answer(response, parse_mode='HTML')

@dp.message(Command("check"))
async def check_chapters(message: Message):
    new_chapters_found = await check_new_chapters()
    if not new_chapters_found:
        # Если новые главы не найдены, отправляем последние главы
        await last_chapter(message)
    else:
        await message.answer("Проверка завершена. Новые главы, если они появились, были отправлены.")

async def on_startup():
    await fetch_boosty_chapters()
    asyncio.create_task(check_updates())

if __name__ == '__main__':
    dp.startup.register(on_startup)
    dp.run_polling(bot)
EOF

# Создание файла службы systemd
sudo tee $SERVICE_FILE > /dev/null <<EOF
[Unit]
Description=Telegram Bot
After=network.target

[Service]
User=$(whoami)
WorkingDirectory=$BOT_DIR
ExecStart=$VENV_DIR/bin/python $BOT_DIR/$SCRIPT_NAME
Restart=always
RestartSec=10
Environment="PATH=$VENV_DIR/bin"

[Install]
WantedBy=multi-user.target
EOF

# Перезагрузите конфигурацию systemd, активируйте и запустите службу
sudo systemctl daemon-reload
sudo systemctl enable telegram_bot
sudo systemctl start telegram_bot

echo "Настройка завершена. Бот должен быть запущен и работать в фоне."
