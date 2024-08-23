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
notified_chapters_webnovel = set()
notified_chapters_boosty = set()

# Храним информацию о том, какие сообщения были отправлены в чаты
sent_messages = {}  # Ключи: chat_id, Значения: множество отправленных сообщений

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
                    ]
                    return filtered_chapters
                else:
                    logging.error(f'Ошибка при запросе страницы Boosty: {response.status}')
                    return []
    except Exception as e:
        logging.error(f'Ошибка при запросе Boosty: {e}')
        return []

async def check_new_chapters():
    global last_chapters_webnovel, last_chapters_boosty, notified_chapters_webnovel, notified_chapters_boosty

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
    boosty_chapters = await fetch_boosty_chapters()
    if boosty_chapters:
        # Обновляем последние две главы и показываем их в обратном порядке
        if boosty_chapters and (not last_chapters_boosty or boosty_chapters[0] != last_chapters_boosty[0]):
            last_chapters_boosty = boosty_chapters[:2]
            last_chapters_boosty.reverse()  # Инвертируем порядок глав

        for chapter in last_chapters_boosty:
            if chapter not in notified_chapters_boosty:
                await notify_chats(f"🚀 Вышла новая глава на Boosty: {chapter}")
                notified_chapters_boosty.add(chapter)
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
    chat_data = load_chat_data()
    for chat_id in chat_data.get('chats', []):
        chat_id_str = str(chat_id)
        
        # Проверяем, если сообщение уже было отправлено в этот чат
        if chat_id_str not in sent_messages:
            sent_messages[chat_id_str] = set()
        
        # Проверяем, если сообщение уже было отправлено в этот чат
        if message_text not in sent_messages[chat_id_str]:
            await bot.send_message(chat_id, message_text)
            sent_messages[chat_id_str].add(message_text)

async def on_startup():
    chat_data = load_chat_data()
    if chat_data.get('chats'):
        # Initialize `notified_chapters_boosty` from chat data if needed
        pass

    asyncio.create_task(check_updates())

@dp.message(CommandStart())
async def send_welcome(message: types.Message):
    await message.reply("Привет! Я бот, который уведомляет о новых главах на Webnovel и Boosty.")

@dp.message(Command("last"))
async def last_chapter(message: types.Message):
    webnovel_chapters = "\n".join(last_chapters_webnovel)
    boosty_chapters = "\n".join(last_chapters_boosty)

    response = (
        f"<b>Новые главы на <a href='{URL_WEBNOVEL}'>Webnovel</a>:</b>\n{webnovel_chapters}\n\n"
        f"<b>Новые главы на <a href='{URL_BOOSTY}'>Boosty</a>:</b>\n{boosty_chapters}"
    )

    await message.answer(response, parse_mode='HTML')

@dp.message(Command("check"))
async def check_chapters(message: Message):
    new_chapters_found = await check_new_chapters()
    if not new_chapters_found:
        await last_chapter(message)
    else:
        await message.answer("Проверка завершена. Новые главы, если они появились, были отправлены.")

@dp.message(Command("ban"))
async def ban_command(message: Message):
    user_name = message.from_user.username
    if user_name == 'dupl1citous':
        response_text = "Все пользователи покинули чат и были заменены на ИИ. 🤖"
    elif user_name == 'AtLasFP':
        response_text = "Не получится, главы сами себя не переведут. 📚"
    else:
        response_text = f"Поняла, начинаю удаление пользователя {user_name} и замену индивида на ИИ... 🤖"

    await message.reply(response_text)

@dp.message()
async def greet_new_member(message: types.Message):
    if message.chat.type == 'group':
        new_members = message.new_chat_members
        for member in new_members:
            webnovel_chapters = "\n".join(last_chapters_webnovel)
            boosty_chapters = "\n".join(last_chapters_boosty)

            welcome_text = (
                f"Добро пожаловать, {member.full_name}. Здесь обсуждается актуальный онгоинг Теневого Раба. "
                f"Если вы не хотите видеть спойлеры или читаете главы в телеграм канале, то вам сюда: "
                f"https://t.me/shad0wslave_chat. Актуальные правила чата находятся в закрепленных сообщениях.\n\n"
                f"<b>Новые главы на <a href='{URL_WEBNOVEL}'>Webnovel</a>:</b>\n{webnovel_chapters}\n\n"
                f"<b>Новые главы на <a href='{URL_BOOSTY}'>Boosty</a>:</b>\n{boosty_chapters}"
            )
            await message.reply(welcome_text, parse_mode='HTML')

        chat_data = load_chat_data()
        chat_id = str(message.chat.id)
        if chat_id not in chat_data.get('chats', []):
            chat_data['chats'].append(chat_id)
            save_chat_data(chat_data)

def load_chat_data():
    try:
        with open('chat_data.json', 'r') as file:
            return json.load(file)
    except (FileNotFoundError, json.JSONDecodeError):
        return {'chats': []}

def save_chat_data(chat_data):
    with open('chat_data.json', 'w') as file:
        json.dump(chat_data, file)

if __name__ == '__main__':
    dp.startup.register(on_startup)
    dp.run_polling(bot)
EOF

cat << 'EOF' > chat_data.json
{
  "chats": []
}
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
