#!/bin/bash

# Убедитесь, что скрипт выполняется с правами суперпользователя
if [[ $EUID -ne 0 ]]; then
   echo "Этот скрипт должен быть выполнен от имени root." 1>&2
   exit 1
fi

# Установите необходимые пакеты
apt update
apt install -y python3 python3-venv python3-pip git

# Создайте директорию для бота и перейдите в неё
mkdir -p /opt/my_bot
cd /opt/my_bot

# Создайте виртуальное окружение и активируйте его
python3 -m venv venv
source venv/bin/activate

# Установите необходимые библиотеки
pip install aiogram

# Создайте файл с кодом бота
cat << 'EOF' > bot.py
import asyncio
import logging
import json
from aiogram import Bot, Dispatcher
from aiogram.types import Message
from aiogram.filters import Command
from aiogram.client.session.aiohttp import AiohttpSession
from aiogram.client.bot import DefaultBotProperties
from datetime import datetime, timedelta

# Конфигурация
API_TOKEN = "7295106138:AAGUaMjkPqCC-bjRyS_ENKRz0H93wHGY8ds"

# Значения выигрышей и проигрышей
JACKPOT = 2000
WIN = 1000
LOOSE = -100
RESET_BALANCE = 1000

# Ограничения
COOLDOWN_TIME = timedelta(minutes=30)
DELETE_TIME = 5
PRISON_TIME = timedelta(hours=2)
DATA_FILE = "user_data.json"

# Администраторы
ADMIN_USERS = {6273910889: "Admin1", 987654321: "Admin2"}  # user_id: name

# Инициализация бота и диспетчера
default_properties = DefaultBotProperties(parse_mode="HTML")
bot = Bot(token=API_TOKEN, session=AiohttpSession(), default=default_properties)
dp = Dispatcher()

# Хэлпер-функции
def load_data():
    try:
        with open(DATA_FILE, "r") as f:
            return json.load(f)
    except FileNotFoundError:
        return {}
    except json.JSONDecodeError:
        logging.error("Ошибка чтения данных из файла JSON.")
        return {}

def save_data(data):
    with open(DATA_FILE, "w") as f:
        json.dump(data, f, indent=4)

user_data = load_data()

def update_balance(user_id, amount, use_ticket=False):
    if not isinstance(user_id, int) or not isinstance(amount, (int, float)):
        logging.error("Invalid user_id or amount type")
        return

    if user_id not in user_data:
        user_data[user_id] = {"balance": RESET_BALANCE, "last_action": {"🎰": None, "🎯": None, "🎲": None}, "prison_until": None, "tickets": 0}

    user_data[user_id]["balance"] += amount
    if user_data[user_id]["balance"] < 0:
        user_data[user_id]["prison_until"] = (datetime.now() + PRISON_TIME).isoformat()
        user_data[user_id]["balance"] = 0


def get_balance(user_id):
    return user_data.get(user_id, {}).get("balance", RESET_BALANCE)

def in_prison(user_id):
    prison_until = user_data.get(user_id, {}).get("prison_until")
    if not prison_until:
        return False
    if datetime.now() >= datetime.fromisoformat(prison_until):
        user_data[user_id]["prison_until"] = None
        return False
    return True

def can_send_sticker(user_id, emoji):
    if in_prison(user_id):
        return False

    last_action = user_data.get(user_id, {}).get("last_action", {}).get(emoji)
    if not last_action or datetime.now() - datetime.fromisoformat(last_action) > COOLDOWN_TIME:
        return True
    return False

# Обработчик попадания в тюрьму
async def handle_prison(user_id, chat_id):
    prison_until = datetime.fromisoformat(user_data[user_id]["prison_until"])
    remaining_time = (prison_until - datetime.now()).seconds // 60
    await send_and_delete_message(chat_id, f"Вы в тюрьме! Осталось ждать {remaining_time} минут.")


async def send_and_delete_message(chat_id, text):
    # Отправка сообщения
    message = await bot.send_message(chat_id, text)
    
    # Асинхронное удаление сообщения через некоторое время
    asyncio.create_task(delete_message_later(chat_id, message.message_id))

async def delete_message_later(chat_id, message_id):
    # Задержка перед удалением
    await asyncio.sleep(DELETE_TIME)
    await bot.delete_message(chat_id, message_id)

# Обработчики стикеров
async def handle_dice(message: Message):
    user_id = message.from_user.id
    chat_id = message.chat.id
    user = message.from_user
    emoji = message.dice.emoji

    if in_prison(user_id):
        prison_until = datetime.fromisoformat(user_data[user_id]["prison_until"])
        remaining_time = (prison_until - datetime.now()).seconds // 60
        await send_and_delete_message(chat_id, f"{user.full_name}, вы в тюрьме! Осталось ждать {remaining_time} минут.")
        await bot.delete_message(chat_id, message.message_id)
        return

    if not can_send_sticker(user_id, emoji):
        await bot.delete_message(chat_id, message.message_id)
        return

    if emoji == "🎰":
        dice_value = message.dice.value

        if dice_value == 64:
            update_balance(user_id, JACKPOT)
            await bot.send_message(chat_id, f"{user.full_name}, поздравляем! Три семерки! 🎉 Джекпот! Вы получили {JACKPOT} монет.")
        elif dice_value in [1, 22, 43]:
            update_balance(user_id, WIN)
            await bot.send_message(chat_id, f"{user.full_name}, вы выиграли! Вы получили {WIN} монет.")
        else:
            update_balance(user_id, LOOSE)
            await send_and_delete_message(chat_id, f"{user.full_name}, Результат: {dice_value}. Неудача! Вы потеряли {abs(LOOSE)} монет.")

    elif emoji == "🎯":
        dice_value = message.dice.value
        if dice_value == 6:
            update_balance(user_id, WIN)
            await bot.send_message(chat_id, f"{user.full_name}, точный выстрел! 🎯 Вы получили {WIN} монет.")
        else:
            balance = get_balance(user_id)
            update_balance(user_id, -(balance // 2))
            await send_and_delete_message(chat_id, f"{user.full_name}, промах! Ваш баланс уменьшен вдвое.")

    elif emoji == "🎲":
        dice_value = message.dice.value
        if dice_value in [1, 2, 3]:
            multiplier = {1: 4, 2: 3, 3: 2}[dice_value]
            balance = get_balance(user_id)
            update_balance(user_id, -(balance // multiplier))
            await send_and_delete_message(chat_id, f"{user.full_name}, результат: {dice_value}. Ваш баланс уменьшен в {multiplier} раза.")
        else:
            multiplier = {4: 2, 5: 3, 6: 4}[dice_value]
            update_balance(user_id, get_balance(user_id) * (multiplier - 1))
            await bot.send_message(chat_id, f"{user.full_name}, результат: {dice_value}. Ваш баланс увеличен в {multiplier} раза.")

    user_data[user_id]["last_action"][emoji] = datetime.now().isoformat()
    save_data(user_data)  # Save data after the action
    await delete_message_later(chat_id, message.message_id)

async def admin_dice_command(message: Message):
    user_id = message.from_user.id
    chat_id = message.chat.id

    if user_id not in ADMIN_USERS:
        await send_and_delete_message(chat_id, "У вас нет прав для выполнения этой команды.")
        await bot.delete_message(chat_id, message.message_id)
        return

    dice_message = await bot.send_dice(chat_id, emoji="🎲")
    dice_value = dice_message.dice.value

    if dice_value == 6:
        await bot.send_message(chat_id, f"Результат 🎲: виновен.")
    else:
        await bot.send_message(chat_id, f"Результат 🎲: невиновен.")

async def check_balance(message: Message):
    user_id = message.from_user.id
    balance = get_balance(user_id)
    await send_and_delete_message(message.chat.id, f"Ваш баланс: {balance} монет.")
    await delete_message_later(message.chat.id, message.message_id)

async def show_top(message: Message):
    top_users = sorted(user_data.items(), key=lambda x: x[1]["balance"], reverse=True)[:10]
    leaderboard = "\n".join([f"{i+1}. {ADMIN_USERS.get(int(user_id), user_id)}: {data['balance']} монет" for i, (user_id, data) in enumerate(top_users)])
    await send_and_delete_message(message.chat.id, f"<b>Топ 10 пользователей:</b>\n{leaderboard}")
    await delete_message_later(message.chat.id, message.message_id)



async def handle_message(message: Message):
    user_id = message.from_user.id
    chat_id = message.chat.id
    
    if message.text.startswith('/'):
        # Выполняем команду, если это команда
        if message.text.startswith('/balance'):
            await check_balance(message)
        elif message.text.startswith('/top'):
            await show_top(message)
        elif message.text.startswith('/justice'):
            await admin_dice_command(message)

        # Удаляем команду после выполнения
        await delete_message_later(chat_id, message.message_id)
        return  

    if in_prison(user_id):
        await handle_prison(user_id, chat_id)
        return

if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)

    user_data = load_data()

    dp.message.register(handle_dice, lambda message: message.dice and message.dice.emoji in ["🎰", "🎯", "🎲"])
    dp.message.register(check_balance, Command(commands=["balance"]))
    dp.message.register(show_top, Command(commands=["top"]))
    dp.message.register(admin_dice_command, Command(commands=["justice"]))
    dp.message.register(handle_message)

    dp.run_polling(bot)
EOF

# Создайте файл сервиса для systemd
cat << EOF > /etc/systemd/system/my_bot.service
[Unit]
Description=My Telegram Bot
After=network.target

[Service]
ExecStart=/opt/my_bot/venv/bin/python /opt/my_bot/bot.py
WorkingDirectory=/opt/my_bot
User=ubuntu
Group=ubuntu
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Перезагрузите systemd и запустите службу
systemctl daemon-reload
systemctl start my_bot.service
systemctl enable my_bot.service

echo "Бот установлен и запущен. Проверьте статус службы с помощью 'systemctl status my_bot.service'."
