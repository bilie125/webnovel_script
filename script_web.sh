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
pip install aiogram beautifulsoup4 aiohttp cloudscraper

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
from datetime import datetime
import cloudscraper

API_TOKEN = '7516735071:AAHEpUrjHZKVESc8Zx6CLJ9hNVpTT3qYmGk'
URL_WEBNOVEL = 'https://www.webnovel.com/book/22196546206090805/catalog'
URL_WEBNOVEL_TRUE = 'https://www.webnovel.com/book/22196546206090805'
URL_BOOSTY = 'http://proxy.tfdracing.nl/?q=aHR0cHM6Ly9ib29zdHkudG8vc2hhZG93X3NsYXZl&hl'
URL_BOOSTY_TRUE = 'https://boosty.to/shadow_slave'


# Инициализация бота и диспетчера
bot = Bot(token=API_TOKEN)
dp = Dispatcher()

# Файл для хранения ID сообщений
CHAT_MESSAGE_ID_FILE = 'chat_message_ids.json'
NOTIFIED_FILE = 'notified_chapters.json'

def load_notified_chapters():
    try:
        with open(NOTIFIED_FILE, 'r', encoding='utf-8') as f:
            data = json.load(f)
        return {
            'webnovel': set(data.get('webnovel', [])),
            'boosty': set(data.get('boosty', [])),
            'boosty_en': set(data.get('boosty_en', []))
        }
    except (FileNotFoundError, json.JSONDecodeError):
        return {
            'webnovel': set(),
            'boosty': set(),
            'boosty_en': set()
        }

def save_notified_chapters():
    data = {
        'webnovel': list(notified_chapters_webnovel),
        'boosty': list(notified_chapters_boosty),
        'boosty_en': list(notified_english_chapters_boosty)
    }
    with open(NOTIFIED_FILE, 'w', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False, indent=4)

def load_chat_message_ids():
    try:
        with open(CHAT_MESSAGE_ID_FILE, 'r', encoding='utf-8') as file:
            return json.load(file)
    except (FileNotFoundError, json.JSONDecodeError):
        return {}

def save_chat_message_ids(data):
    with open(CHAT_MESSAGE_ID_FILE, 'w', encoding='utf-8') as file:
        json.dump(data, file, ensure_ascii=False, indent=4)

# Загружаем сохранённые сообщения
chat_message_ids = load_chat_message_ids()

# В памяти храним последние две главы
last_chapters_webnovel = []
last_chapters_boosty = []
last_english_chapters_boosty = []

# Для хранения глав на английском
notified_chapters_webnovel = set()
notified_chapters_boosty = set()
notified_english_chapters_boosty = set()

# Для уведомления о главах на английском
chapter_times = {
    'webnovel': {},
}

# Функция для получения времени в строковом формате
def get_time_string(timestamp):
    return timestamp.strftime("%Y-%m-%d %H:%M:%S") if timestamp else "Неизвестно"

# Храним информацию о том, какие сообщения были отправлены в чаты
sent_messages = {}  # Ключи: chat_id, Значения: множество отправленных сообщений

# Храним chat_id в коде
CHAT_DATA_FILE = 'chat_data.json'
def load_chat_data():
    try:
        with open(CHAT_DATA_FILE, 'r', encoding='utf-8') as file:
            return json.load(file)
    except FileNotFoundError:
        return {'chats': []}

def save_chat_data(data):
    with open(CHAT_DATA_FILE, 'w', encoding='utf-8') as file:
        json.dump(data, file, ensure_ascii=False, indent=4)

chat_data = load_chat_data()

def generate_response():
    """Генерация текста для сообщения"""
    webnovel_chapters = "\n".join(
        [f"{chapter} (Время выхода: {get_time_string(chapter_times['webnovel'].get(chapter))})" 
         for chapter in last_chapters_webnovel]
    )
    boosty_chapters = "\n".join(last_chapters_boosty)
    return (
        f"<b>Новые главы на <a href='{URL_WEBNOVEL_TRUE}'>Webnovel</a>:</b>\n{webnovel_chapters}\n\n"
        f"<b>Новые главы на <a href='{URL_BOOSTY_TRUE}'>Boosty</a>:</b>\n{boosty_chapters}\n\n"
    )

async def update_chapter_message():
    """Обновляет сообщения во всех чатах при старте бота"""
    response = generate_response()
    for chat_id_str, message_id in chat_message_ids.items():
        try:
            await bot.edit_message_text(
                response,
                chat_id=int(chat_id_str),
                message_id=message_id,
                parse_mode='HTML',
                disable_web_page_preview=True
            )
            logging.info(f"✅ Обновлено сообщение в чате {chat_id_str}")
        except Exception as e:
            logging.error(f"❌ Ошибка обновления в чате {chat_id_str}: {e}")

@dp.message(Command("subscribe"))
async def subscribe_chat(message: Message):
    chat_id = str(message.chat.id)
    if chat_id not in chat_data['chats']:
        chat_data['chats'].append(chat_id)
        save_chat_data(chat_data)
        await message.answer("Чат успешно добавлен в список для получения обновлений!")
    else:
        await message.answer("Чат уже находится в списке для получения обновлений.")

async def on_startup():
    if chat_data.get('chats'):
        logging.info(f"Загружены чаты: {chat_data['chats']}")
    asyncio.create_task(check_updates())
    await update_chapter_message()

@dp.message(Command("unsubscribe"))
async def unsubscribe_chat(message: Message):
    chat_id = str(message.chat.id)
    if chat_id in chat_data['chats']:
        chat_data['chats'].remove(chat_id)
        save_chat_data(chat_data)
        await message.answer("Чат успешно удалён из списка подписки.")
    else:
        await message.answer("Чат не был подписан.")

# Включение логирования
logging.basicConfig(level=logging.INFO)

async def fetch_webnovel_chapter():
    """Получение последней главы с Webnovel с обходом Cloudflare и опциональным прокси"""
    headers = {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36'
    }
    try:
        # Используем cloudscraper для обхода Cloudflare
        scraper = cloudscraper.create_scraper(
            browser={'custom': headers['User-Agent']}
        )
        html = scraper.get(URL_WEBNOVEL).text

        soup = BeautifulSoup(html, 'html.parser')
        chapter_tag = soup.find('a', class_='ell lst-chapter dib vam')
        chapter_name = chapter_tag.text.strip() if chapter_tag else None
        if chapter_name and chapter_name not in chapter_times['webnovel']:
            chapter_times['webnovel'][chapter_name] = datetime.now()
            return chapter_name
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
                    chapters = soup.find_all('div', class_='PostSubscriptionBlock-scss--module_title_JRdhp')
                    filtered_chapters = [
                        chapter.get_text(strip=True) for chapter in chapters
                        if re.match(r'^Глава \d+: .+$', chapter.get_text(strip=True))
                    ]
                    english_chapters = [
                        chapter.get_text(strip=True) for chapter in chapters
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
        if latest_chapter_webnovel not in notified_chapters_webnovel:
            await notify_chats(f"📖 Вышла новая глава на Webnovel: {latest_chapter_webnovel}")
            notified_chapters_webnovel.add(latest_chapter_webnovel)
            new_chapters_found = True

    # Обработка глав Boosty
    boosty_chapters, english_chapters = await fetch_boosty_chapters()

    if boosty_chapters and (not last_chapters_boosty or boosty_chapters[0] != last_chapters_boosty[0]):
        last_chapters_boosty = boosty_chapters[:2]
        last_chapters_boosty.reverse()
        for chapter in last_chapters_boosty:
            if chapter not in notified_chapters_boosty:
                await notify_chats(f"🚀 Вышла новая глава на Boosty: {chapter}")
                notified_chapters_boosty.add(chapter)
                new_chapters_found = True

    if english_chapters and (not last_english_chapters_boosty or english_chapters[0] != last_english_chapters_boosty[0]):
        last_english_chapters_boosty = english_chapters[:2]
        last_english_chapters_boosty.reverse()
        for chapter in last_english_chapters_boosty:
            if chapter not in notified_english_chapters_boosty:
                await notify_chats(f"🚀📖 Вышла новая глава на английском на Boosty: {chapter}")
                notified_english_chapters_boosty.add(chapter)
                new_chapters_found = True

    if new_chapters_found:
        await update_chapter_message()
        save_notified_chapters()
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
        if chat_id_str not in sent_messages:
            sent_messages[chat_id_str] = set()
        if message_text not in sent_messages[chat_id_str]:
            try:
                await bot.send_message(chat_id, message_text, disable_web_page_preview=True)
                sent_messages[chat_id_str].add(message_text)
            except Exception as e:
                logging.error(f"Ошибка при отправке сообщения в чат {chat_id}: {e}")

@dp.message(CommandStart())
async def send_welcome(message: types.Message):
    await message.reply(
        "Привет! Я бот, который уведомляет о новых главах на Webnovel и Boosty.",
        disable_web_page_preview=True
    )

@dp.message(Command("dwfe2324wgrer3ht543thrge5"))
async def last_chapter(message: Message):
    chat_id_str = str(message.chat.id)
    response = generate_response()
    if chat_id_str in chat_message_ids:
        try:
            await bot.edit_message_text(
                response,
                chat_id=message.chat.id,
                message_id=chat_message_ids[chat_id_str],
                parse_mode='HTML',
                disable_web_page_preview=True
            )
            logging.info(f"✅ Сообщение обновлено в чате {chat_id_str}")
        except Exception as e:
            logging.error(f"❌ Ошибка при редактировании сообщения: {e}")
        new_message = await message.answer(response, disable_web_page_preview=True)
        chat_message_ids[chat_id_str] = new_message.message_id
        save_chat_message_ids(chat_message_ids)
    else:
        new_message = await message.answer(response, disable_web_page_preview=True)
        chat_message_ids[chat_id_str] = new_message.message_id
        save_chat_message_ids(chat_message_ids)

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

@dp.message(Command("force_update"))
async def force_update_message(message: Message):
    await check_new_chapters()
    await update_chapter_message()

@dp.message()
async def greet_new_member(message: types.Message):
    if message.chat.type in ['group', 'supergroup']:
        new_members = message.new_chat_members
        if new_members is not None:
            for member in new_members:
                webnovel_chapters = "\n".join(
                    [f"{chapter} (Время выхода: {get_time_string(chapter_times['webnovel'].get(chapter))})"
                     for chapter in last_chapters_webnovel]
                )
                boosty_chapters_russian = "\n".join(last_chapters_boosty)
                welcome_text = (
                    f"Добро пожаловать, {member.full_name}. Здесь обсуждается актуальный онгоинг Теневого Раба. "
                    f"Если вы не хотите видеть спойлеры или читаете главы в телеграм канале, то вам "
                    f"<a href='https://t.me/+j6Phf2Lh0503MjIy'>сюда</a>. "
                    f"Актуальные <a href='https://t.me/c/2079142065/1137454'>правила чата</a> находятся в закрепленных сообщениях.\n\n"
                    f"<b>Новые главы на <a href='{URL_WEBNOVEL_TRUE}'>Webnovel</a>:</b>\n{webnovel_chapters}\n\n"
                    f"<b>Новые главы на <a href='{URL_BOOSTY_TRUE}'>Boosty</a>:</b>\n{boosty_chapters_russian}\n\n"
                )
                await message.reply(welcome_text, parse_mode='HTML', disable_web_page_preview=True)
                chat_id = str(message.chat.id)
                if chat_id not in chat_data.get('chats', []):
                    chat_data['chats'].append(chat_id)
                    logging.info(f'Чат {chat_id} добавлен в память.')
        else:
            logging.warning("Нет новых участников в сообщении.")

if __name__ == '__main__':
    notified = load_notified_chapters()
    notified_chapters_webnovel = notified['webnovel']
    notified_chapters_boosty = notified['boosty']
    notified_english_chapters_boosty = notified['boosty_en']

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

