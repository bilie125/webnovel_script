#!/bin/bash

# Настройки
BOT_DIR="/opt/shadow_slave_bot"
VENV_DIR="$BOT_DIR/botenv"
SERVICE_FILE="/etc/systemd/system/shadow_slave_bot.service"
BOT_SCRIPT="$BOT_DIR/bot.py"

# Обновление системы
sudo apt update
sudo apt upgrade -y

# Установка Python и pip
sudo apt install -y python3 python3-pip python3-venv

# Создание директории для бота
sudo mkdir -p $BOT_DIR

# Перемещение в директорию бота
cd $BOT_DIR

# Создание виртуального окружения
python3 -m venv botenv

# Активация виртуального окружения и установка зависимостей
source botenv/bin/activate
pip install aiogram beautifulsoup4 aiohttp

# Создание файла конфигурации
echo 'API_TOKEN = "7516735071:AAEvgxMXIEx06sSJ2Aq_YHR8AqYMGP7kL1k"' > config.py

# Создание скрипта бота
cat << 'EOF' > $BOT_SCRIPT
import logging
import asyncio
import json
from aiogram import Bot, Dispatcher, types
from aiogram.filters import Command, CommandStart
from aiogram.types import Message
from bs4 import BeautifulSoup
import aiohttp
import re

API_TOKEN = '7516735071:AAEvgxMXIEx06sSJ2Aq_YHR8AqYMGP7kL1k'
URL_WEBNOVEL = 'https://webnovel.com/book/shadow-slave_22196546206090805/catalog'
URL_BOOSTY = 'https://boosty.to/shadow_slave'

# Инициализация бота и диспетчера
bot = Bot(token=API_TOKEN)
dp = Dispatcher()

# В памяти храним последние две главы
last_chapters_webnovel = []
last_chapters_boosty = []
last_english_chapters_boosty = []  # Для хранения глав на английском
notified_chapters_webnovel = set()
notified_chapters_boosty = set()
notified_english_chapters_boosty = set()  # Для уведомления о главах на английском

# Храним информацию о том, какие сообщения были отправлены в чаты
sent_messages = {}  # Ключи: chat_id, Значения: множество отправленных сообщений

# Храним chat_id в коде
chat_data = {
    'chats': ["-1002079142065",]
}

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
    headers = {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/58.0.3029.110 Safari/537.36'
    }
    
    try:
        async with aiohttp.ClientSession() as session:
            async with session.get(URL_BOOSTY, headers=headers) as response:
                if response.status == 200:
                    html = await response.text()
                    soup = BeautifulSoup(html, 'html.parser')
                    chapters = soup.find_all('div', class_='PostSubscriptionBlock_title_WXCN0')

                    # Фильтр глав на русском языке
                    filtered_chapters = [
                        chapter.get_text(strip=True)
                        for chapter in chapters
                        if re.match(r'^Глава \d+: .+$', chapter.get_text(strip=True))
                    ]
                    
                    # Фильтр глав на английском
                    english_chapters = [
                        chapter.get_text(strip=True)
                        for chapter in chapters
                        if re.match(r'^\d+(-\d+)? на английском$', chapter.get_text(strip=True))
                    ]
                    
                    return filtered_chapters, english_chapters
                else:
                    logging.error(f'Ошибка при запросе страницы Boosty: {response.status}')
                    return [], []
    except Exception as e:
        logging.error(f'Ошибка при запросе Boosty: {e}')
        return [], []

async def check_new_chapters():
    global last_chapters_webnovel, last_chapters_boosty, last_english_chapters_boosty
    global notified_chapters_webnovel, notified_chapters_boosty, notified_english_chapters_boosty

    latest_chapter_webnovel = await fetch_webnovel_chapter()
    new_chapters_found = False

    # Обработка глав Webnovel
    if latest_chapter_webnovel and (not last_chapters_webnovel or latest_chapter_webnovel != last_chapters_webnovel[-1]):
        last_chapters_webnovel.append(latest_chapter_webnovel)
        if len(last_chapters_webnovel) > 2:
            last_chapters_webnovel.pop(0)

        # Отправляем сообщение, если глава новая
        if latest_chapter_webnovel not in notified_chapters_webnovel:
            await notify_chats(f"📖 Вышла новая глава на Webnovel: {latest_chapter_webnovel}")
            notified_chapters_webnovel.add(latest_chapter_webnovel)
            new_chapters_found = True

    # Обработка глав Boosty
    boosty_chapters, english_chapters = await fetch_boosty_chapters()

    # Обработка русских глав
    if boosty_chapters and (not last_chapters_boosty or boosty_chapters[0] != last_chapters_boosty[0]):
        last_chapters_boosty = boosty_chapters[:2]
        last_chapters_boosty.reverse()  # Инвертируем порядок глав

    for chapter in last_chapters_boosty:
        if chapter not in notified_chapters_boosty:
            await notify_chats(f"🚀 Вышла новая глава на Boosty: {chapter}")
            notified_chapters_boosty.add(chapter)
            new_chapters_found = True

    # Обработка английских глав
    if english_chapters and (not last_english_chapters_boosty or english_chapters[0] != last_english_chapters_boosty[0]):
        last_english_chapters_boosty = english_chapters[:2]
        last_english_chapters_boosty.reverse()  # Инвертируем порядок глав

    for chapter in last_english_chapters_boosty:
        if chapter not in notified_english_chapters_boosty:
            await notify_chats(f"🚀📖 Вышла новая глава на английском на Boosty: {chapter}")
            notified_english_chapters_boosty.add(chapter)
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
        await asyncio.sleep(8)  # Опрос каждые 8 секунд

async def notify_chats(message_text):
    for chat_id in chat_data.get('chats', []):
        chat_id_str = str(chat_id)
        
        # Проверяем, если сообщение уже было отправлено в этот чат
        if chat_id_str not in sent_messages:
            sent_messages[chat_id_str] = set()
        
        # Проверяем, если сообщение уже было отправлено в этот чат
        if message_text not in sent_messages[chat_id_str]:
            try:
                await bot.send_message(
                    chat_id, 
                    message_text, 
                    disable_web_page_preview=True  # Отключаем предпросмотр ссылок
                )
                sent_messages[chat_id_str].add(message_text)
            except Exception as e:
                logging.error(f"Ошибка при отправке сообщения в чат {chat_id}: {e}")

async def on_startup():
    if chat_data.get('chats'):
        # Initialize `notified_chapters_boosty` from chat data if needed
        pass

    asyncio.create_task(check_updates())

@dp.message(CommandStart())
async def send_welcome(message: types.Message):
    await message.reply(
        "Привет! Я бот, который уведомляет о новых главах на Webnovel и Boosty.",
        disable_web_page_preview=True
    )

@dp.message(Command("last"))
async def last_chapter(message: types.Message):
    webnovel_chapters = "\n".join(last_chapters_webnovel)
    boosty_chapters = "\n".join(last_chapters_boosty)
    english_chapters = "\n".join(last_english_chapters_boosty)

    response = (
        f"<b>Новые главы на <a href='{URL_WEBNOVEL}'>Webnovel</a>:</b>\n{webnovel_chapters}\n\n"
        f"<b>Новые главы на <a href='{URL_BOOSTY}'>Boosty</a>:</b>\n{boosty_chapters}\n\n"
        f"<b>Новые главы на английском на <a href='{URL_BOOSTY}'>Boosty</a>:</b>\n{english_chapters}"
    )

    await message.answer(response, parse_mode='HTML', disable_web_page_preview=True)

@dp.message(Command("check"))
async def check_chapters(message: Message):
    new_chapters_found = await check_new_chapters()
    if not new_chapters_found:
        await last_chapter(message)
    else:
        await message.answer(
            "Проверка завершена. Новые главы, если они появились, были отправлены.",
            disable_web_page_preview=True
        )

if __name__ == '__main__':
    dp.startup.register(on_startup)
    dp.run_polling(bot)
EOF

# Создание системного сервиса
sudo bash -c "cat << EOF > $SERVICE_FILE
[Unit]
Description=Shadow Slave Bot
After=network.target

[Service]
User=$USER
WorkingDirectory=$BOT_DIR
ExecStart=$VENV_DIR/bin/python $BOT_SCRIPT
Restart=always

[Install]
WantedBy=multi-user.target
EOF"

# Перезагрузка конфигурации systemd и запуск сервиса
sudo systemctl daemon-reload
sudo systemctl start shadow_slave_bot
sudo systemctl enable shadow_slave_bot

echo "Установка завершена. Бот запущен и настроен как системный сервис."
