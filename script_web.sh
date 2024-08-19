#!/bin/bash

# Обновление системы
sudo apt update && sudo apt upgrade -y

# Установка Python и pip
sudo apt install -y python3 python3-pip

# Установка необходимых Python библиотек
pip3 install aiogram requests beautifulsoup4

# Создание рабочего каталога
mkdir -p ~/my_telegram_bot
cd ~/my_telegram_bot

# Создание файла бота
cat << EOF > bot.py
import logging
import requests
from bs4 import BeautifulSoup
from aiogram import Bot, Dispatcher, types
from aiogram.filters import Command, CommandStart
import asyncio

API_TOKEN = '7516735071:AAEvgxMXIEx06sSJ2Aq_YHR8AqYMGP7kL1k'
GROUP_CHAT_ID = '-1002079142065'  # Замените на ID вашей группы

# Включение логирования
logging.basicConfig(level=logging.INFO)

# Инициализация бота и диспетчера
bot = Bot(token=API_TOKEN)
dp = Dispatcher()

# В памяти храним последние две главы
last_chapters = []

# URL каталога книги
URL = "https://webnovel.com/book/shadow-slave_22196546206090805/catalog"

def get_latest_chapter():
    """Парсит сайт и возвращает название последней главы."""
    headers = {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36'
    }
    try:
        response = requests.get(URL, headers=headers)
        response.raise_for_status()
        soup = BeautifulSoup(response.content, 'html.parser')
        chapter_tag = soup.find('a', class_='ell lst-chapter dib vam')
        return chapter_tag.text.strip() if chapter_tag else None
    except requests.RequestException as e:
        logging.error(f"Ошибка при запросе страницы: {e}")
        return None

@dp.message(CommandStart())
async def send_welcome(message: types.Message):
    await message.reply("Привет! Я бот, который уведомляет о новых главах на Webnovel.")

@dp.message(Command('check'))
async def check_chapters(message: types.Message):
    latest_chapter = get_latest_chapter()
    if not latest_chapter:
        await message.reply("Не удалось получить последнюю главу.")
        return

    if latest_chapter in last_chapters:
        await message.reply("Новых глав нет.")
    else:
        last_chapters.append(latest_chapter)
        if len(last_chapters) > 2:
            last_chapters.pop(0)
        await message.reply(f"Вышла новая глава: {latest_chapter}")

@dp.message(Command('last'))
async def last_chapter(message: types.Message):
    if len(last_chapters) >= 2:
        await message.reply(f"Последние две главы:\n1. {last_chapters[-2]}\n2. {last_chapters[-1]}")
    elif len(last_chapters) == 1:
        await message.reply(f"Последняя глава: {last_chapters[-1]}")
    else:
        await message.reply("Нет данных о главах.")

async def check_new_chapter():
    """Функция для проверки новых глав."""
    latest_chapter = get_latest_chapter()
    if latest_chapter:
        if not last_chapters or latest_chapter != last_chapters[-1]:
            last_chapters.append(latest_chapter)
            if len(last_chapters) > 2:
                last_chapters.pop(0)
            await bot.send_message(chat_id=GROUP_CHAT_ID, text=f"Вышла новая глава: {latest_chapter}")

async def check_new_chapter_periodically():
    """Функция для периодической проверки каждые 80 секунд."""
    while True:
        await check_new_chapter()
        await asyncio.sleep(80)  # Опрос каждые 80 секунд

async def main():
    """Основная функция для запуска бота."""
    await dp.start_polling(bot)

if __name__ == '__main__':
    # Запуск бота
    logging.basicConfig(level=logging.INFO)
    asyncio.run(main())
EOF

# Создание файла службы systemd
cat << EOF | sudo tee /etc/systemd/system/mybot.service
[Unit]
Description=My Telegram Bot
After=network.target

[Service]
ExecStart=/usr/bin/python3 /home/$(whoami)/my_telegram_bot/bot.py
WorkingDirectory=/home/$(whoami)/my_telegram_bot
Restart=always
User=$(whoami)
Group=$(whoami)

[Install]
WantedBy=multi-user.target
EOF

# Перезагрузка systemd и запуск службы
sudo systemctl daemon-reload
sudo systemctl start mybot.service
sudo systemctl enable mybot.service

# Проверка статуса службы
sudo systemctl status mybot.service
