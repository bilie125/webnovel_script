#!/bin/bash

# Обновление списка пакетов
sudo apt update

# Установка Python и pip
sudo apt install -y python3 python3-pip

# Установка необходимых библиотек
pip3 install aiogram beautifulsoup4 requests EbookLib

# Создание директории для бота
mkdir -p ~/telegram_download_bot
cd ~/telegram_download_bot

# Создание файла с кодом бота
cat << EOF > download_bot.py
import json
import os
import re
import time
import requests
from bs4 import BeautifulSoup
from aiogram import Bot, Dispatcher, Router, types
from aiogram.types import FSInputFile
from aiogram.filters import Command
import asyncio
import logging
from ebooklib import epub

# Настройка логирования
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

TOKEN = '8148182667:AAEi0udksKqScHEtzDlxAbDXRrRpxBCoNus'
bot = Bot(token=TOKEN)
dp = Dispatcher()
router = Router()

# Файлы для хранения данных
LINKS_FILE = 'chapter_links.txt'
USAGE_FILE = 'usage_data.json'
EXCEPTIONS_FILE = 'user_exceptions.json'

# Словари для хранения данных
chapter_links = {}
usage_data = {}
user_exceptions = {}
admin_ids = [684795841,6273910889]  # Замените на ваши ID администраторов

# Функция для загрузки ссылок из файла
def load_links():
    if os.path.exists(LINKS_FILE):
        with open(LINKS_FILE, 'r', encoding='utf-8') as file:
            for line in file:
                match = re.match(r'Глава (\d+): (https://telegra\.ph/Glava-\d+[^\s]*)', line.strip())
                if match:
                    num = int(match.group(1))
                    link = match.group(2)
                    chapter_links[num] = link

# Функция для сохранения ссылок в файл
def save_links():
    with open(LINKS_FILE, 'w', encoding='utf-8') as file:
        for num, link in chapter_links.items():
            file.write(f"Глава {num}: {link}\n")

# Функции для загрузки и сохранения usage_data и исключений
def load_usage_and_exceptions():
    global usage_data, user_exceptions

    if os.path.exists(USAGE_FILE):
        with open(USAGE_FILE, 'r', encoding='utf-8') as file:
            usage_data = json.load(file)

    if os.path.exists(EXCEPTIONS_FILE):
        with open(EXCEPTIONS_FILE, 'r', encoding='utf-8') as file:
            user_exceptions = json.load(file)

def save_usage_data():
    with open(USAGE_FILE, 'w', encoding='utf-8') as file:
        json.dump(usage_data, file)

def save_user_exceptions():
    with open(EXCEPTIONS_FILE, 'w', encoding='utf-8') as file:
        json.dump(user_exceptions, file)

# Функция для получения количества использований
def get_usage_count(user_id, username):
    # Проверяем как user_id, так и username
    if username and username in usage_data:
        return usage_data[username]['count'], usage_data[username]['last_used']
    elif user_id in usage_data:
        return usage_data[user_id]['count'], usage_data[user_id]['last_used']
    return 0, 0

# Функция для обновления количества использований
def update_usage(user_id, username):
    current_time = time.time()
    if username and username in usage_data:
        usage_data[username]['count'] += 1
        usage_data[username]['last_used'] = current_time
    elif user_id in usage_data:
        usage_data[user_id]['count'] += 1
        usage_data[user_id]['last_used'] = current_time
    else:
        # Добавляем запись для username и user_id, если их нет
        if username:
            usage_data[username] = {'count': 1, 'last_used': current_time}
        if user_id:
            usage_data[user_id] = {'count': 1, 'last_used': current_time}

    save_usage_data()

# Функция для проверки исключений
def is_user_exception(user_id, username):
    current_time = time.time()

    # Проверяем для user_id
    if user_id in user_exceptions:
        return current_time < user_exceptions[user_id]
    
    # Проверяем для username
    if username and username in user_exceptions:
        return current_time < user_exceptions[username]
    
    return False


# Обработка новых ссылок в сообщениях
@router.message(lambda message: not message.text.startswith('/'))
async def extract_links(message: types.Message):
    if message.entities:
        for entity in message.entities:
            if entity.type == 'text_link' and entity.url:
                text = message.text[entity.offset:entity.offset + entity.length]
                match = re.match(r'Глава (\d+)', text)
                if match:
                    chapter_number = int(match.group(1))
                    link = entity.url
                    chapter_links[chapter_number] = link

    if chapter_links:
        save_links()

# Функция для получения содержимого главы по ссылке
def get_chapter_content(link):
    logger.info(f"Получение контента главы по ссылке: {link}")
    response = requests.get(link)
    if response.status_code == 200:
        soup = BeautifulSoup(response.content, 'html.parser')

        # Извлечение заголовка главы
        title = soup.find('h1').get_text() if soup.find('h1') else 'Без заголовка'
        
        # Извлечение текста главы (все параграфы в статье)
        content = soup.find_all('p')

        # Фильтрация нежелательных фраз
        text = "\n".join([p.get_text() for p in content if 'Предыдущая глава' not in p.get_text() and 'Следующая глава' not in p.get_text()])

        logger.info(f"Глава успешно получена: {title}")
        return title, text
    else:
        logger.error(f"Ошибка получения контента по ссылке {link}, статус код: {response.status_code}")
    return None, None

# Функция для создания EPUB файла
def create_epub(chapters, epub_file_name):
    book = epub.EpubBook()
    
    # Убираем расширение из имени файла для заголовка
    book_title = os.path.splitext(epub_file_name)[0]
    book.set_title(book_title)
    book.set_language("ru")
    book.add_author("AtLas")  # Замените на нужного автора

    # Добавляем главы в EPUB
    for num, (title, content) in chapters.items():
        chapter = epub.EpubHtml(title=title, file_name=f'chapter_{num}.xhtml', lang='ru')
        chapter_content = f'<h1>{title}</h1><p>{content.replace("\n", "</p><p>")}</p>'
        chapter.set_content(chapter_content)
        book.add_item(chapter)
    
    # Добавляем оглавление
    book.toc = (epub.Link('nav.xhtml', 'Содержание', 'toc'), (chapter for chapter in book.items if isinstance(chapter, epub.EpubHtml)))
    
    # Создаем навигационную страницу
    book.add_item(epub.EpubNav())
    
    # Добавляем CSS стиль
    style = epub.EpubItem(uid="style_nav", file_name="style/nav.css", media_type="text/css", content="BODY { color: black; }")
    book.add_item(style)

    # Указываем, какие элементы книги являются "главными"
    book.spine = ['nav'] + [chapter for chapter in book.items if isinstance(chapter, epub.EpubHtml)]
    
    # Сохраняем EPUB
    epub.write_epub(epub_file_name, book)
    logger.info(f"EPUB файл {epub_file_name} успешно создан.")

# Обработчик команды /add_exception для администраторов
@router.message(Command(commands=["add_exception"]))
async def add_exception(message: types.Message):
    user_id = message.from_user.id
    
    # Проверка на администратора
    if user_id not in admin_ids:
        await message.reply("У вас нет прав для выполнения этой команды.")
        return

    try:
        args = message.text.split()[1:]  # Получаем все аргументы
        if len(args) < 2:
            await message.reply("Использование: /add_exception <user_id или username> <количество_дней>")
            return

        target_user = args[0]
        days = int(args[1])
        exception_time = time.time() + days * 24 * 3600
        
        # Добавляем исключение
        if target_user.isdigit():
            user_id_target = int(target_user)  # user_id
            user_exceptions[user_id_target] = exception_time
            await message.reply(f"Исключение для пользователя с ID {user_id_target} добавлено на {days} дней.")
        else:
            username_target = target_user.lstrip('@')  # Удаляем символ '@' из username, если он есть
            user_exceptions[username_target] = exception_time
            await message.reply(f"Исключение для пользователя @{username_target} добавлено на {days} дней.")

        # Сохраняем исключения в файл
        save_user_exceptions()
        logger.info(f"Администратор {user_id} добавил исключение для пользователя {target_user} на {days} дней.")

    except Exception as e:
        await message.reply(f"Произошла ошибка: {e}")
        logger.error(f"Ошибка при добавлении исключения: {e}")


# Обработчик команды /get_chapters с проверкой исключений
@router.message(Command(commands=["get_chapters"]))
async def get_chapters(message: types.Message):
    user_id = message.from_user.id
    username = message.from_user.username

    # Проверка на администраторов и исключения
    if user_id not in admin_ids and not is_user_exception(user_id, username):
        count, last_used = get_usage_count(user_id, username)

        # Ограничение на 2 использования в день
        if count >= 2 and time.time() - last_used < 24 * 3600:
            await message.reply("Вы использовали свои 2 попытки на сегодня. Попробуйте завтра.")
            return

    try:
        args = message.text.split()[1:]
        if len(args) < 2:
            await message.reply("Укажите диапазон глав, например: /get_chapters 1873 1916")
            return
        
        start = int(args[0])
        end = int(args[1])

        # Проверка на администраторов и исключения
        if user_id not in admin_ids and not is_user_exception(user_id, username):
            count, last_used = get_usage_count(user_id, username)

            # Ограничение на 80 глав за раз
            if end - start + 1 > 80:
                await message.reply("Вы можете запросить не более 80 глав за раз.")
                return

        relevant_links = {num: link for num, link in chapter_links.items() if start <= num <= end}
        if not relevant_links:
            await message.reply("Нет ссылок на главы в указанном диапазоне.")
            return

        chapters = {}
        for num in sorted(relevant_links.keys()):
            link = relevant_links[num]
            title, content = get_chapter_content(link)
            if content:
                chapters[num] = (title, content)

        txt_file_name = f'chapters_{start}_to_{end}.txt'
        with open(txt_file_name, 'w', encoding='utf-8') as file:
            for num, (title, content) in chapters.items():
                file.write(f"{title}\n\n{content}\n\n")

        await message.answer_document(FSInputFile(txt_file_name))

        epub_file_name = f'chapters_{start}_to_{end}.epub'
        create_epub(chapters, epub_file_name)
        await message.answer_document(FSInputFile(epub_file_name))

        os.remove(txt_file_name)
        os.remove(epub_file_name)

        # Обновляем данные использования
        update_usage(user_id, username)

    except Exception as e:
        await message.reply(f"Произошла ошибка: {e}")

# Запуск бота
async def main():
    logger.info("Запуск бота...")
    load_links()
    load_usage_and_exceptions()
    dp.include_router(router)
    await dp.start_polling(bot)

if __name__ == '__main__':
    asyncio.run(main())
EOF

# Установка прав на выполнение
chmod +x download_bot.py

# Создание systemd сервиса
cat << EOF | sudo tee /etc/systemd/system/telegram_download_bot.service
[Unit]
Description=Telegram Bot Service
After=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=$HOME/telegram_download_bot
ExecStart=/usr/bin/python3 $HOME/telegram_download_bot/bot.py
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

# Перезагрузка systemd для обновления конфигурации сервисов
sudo systemctl daemon-reload

# Включение сервиса для автоматического старта
sudo systemctl enable telegram_download_bot.service

# Запуск сервиса
sudo systemctl start telegram_download_bot.service

echo "Бот установлен и запущен. Чтобы проверить статус, используйте: sudo systemctl status telegram_download_bot.service"
