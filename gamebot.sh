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
from aiogram import Bot, Dispatcher
from aiogram.types import Message
from aiogram.filters import Command
from aiogram import F
from aiogram.fsm.storage.memory import MemoryStorage
import asyncio
import json
import os
from datetime import datetime, timedelta

API_TOKEN = '7295106138:AAGUaMjkPqCC-bjRyS_ENKRz0H93wHGY8ds'
DATA_FILE = 'user_balances.json'
START_POINT = 1500
CREDIT_DURATION = timedelta(hours=1)
JAIL_DURATION = timedelta(hours=2)
JAIL_BALANCE = 1000
TIME_LIMIT = timedelta(hours=1)
GAME_LIMIT = 3
LIFE_COST = 1500
LIFE_POINTS = 2000
DELET_TIME = 20
JACKPOT = 2000
WIN = 1500
LOOSE = -100

bot = Bot(token=API_TOKEN)
dp = Dispatcher(storage=MemoryStorage())

def load_data():
    if os.path.exists(DATA_FILE):
        with open(DATA_FILE, 'r') as file:
            return json.load(file)
    return {}

def save_data(data):
    with open(DATA_FILE, 'w') as file:
        json.dump(data, file, indent=4)

chat_user_balances = load_data()

def update_balance(chat_id: int, user_id: int, points: int):
    if chat_id not in chat_user_balances:
        chat_user_balances[chat_id] = {}

    user_data = chat_user_balances[chat_id].get(user_id, {
        "name": "",
        "balance": START_POINT,
        "credit_start_time": None,
        "jail_until": None,
        "jail_count": 0,
        "games_played": [],
        "lives": 0
    })

    now = datetime.now()

    user_data["games_played"] = [timestamp for timestamp in user_data["games_played"] if now - datetime.fromisoformat(timestamp) < TIME_LIMIT]

    if len(user_data["games_played"]) >= GAME_LIMIT:
        chat_user_balances[chat_id][user_id] = user_data
        save_data(chat_user_balances)
        return

    if user_data["jail_until"] and now < datetime.fromisoformat(user_data["jail_until"]):
        chat_user_balances[chat_id][user_id] = user_data
        save_data(chat_user_balances)
        return

    user_data["games_played"].append(now.isoformat())
    user_data["balance"] += points

    if user_data["balance"] < 0 and user_data["credit_start_time"] is None:
        user_data["credit_start_time"] = now.isoformat()
        asyncio.create_task(
            send_and_delete_message(chat_id, f"Дорогой клиент {user_data['name']}, ваш баланс ушел в минус. У вас есть 2 часа на восстановление положительного количества осколков, иначе вы будете отправлены в тюрьму.")
        )

    if user_data["balance"] >= 0:
        user_data["credit_start_time"] = None
        if user_data["jail_until"]:
            jail_until = datetime.fromisoformat(user_data["jail_until"])
            if now >= jail_until:
                user_data["jail_until"] = None
                user_data["balance"] = JAIL_BALANCE

                if user_data["lives"] > 0:
                    user_data["lives"] -= 1
                    user_data["balance"] = 0
                    user_data["balance"] += LIFE_POINTS
                    asyncio.create_task(
                        send_and_delete_message(chat_id, f"{user_data['name']}, воспользовался зачарованием Маски Ткача [Где мой глаз?] и по нитям судьбы нашел лучшую точку выхода из Царства Теней. Найдено {LIFE_POINTS} осколков.")
                    )
                else:
                    asyncio.create_task(
                        send_and_delete_message(chat_id, f"{user_data['name']}, сбежал из Царства Теней. Из жалости Дикие Тени дали вам {JAIL_BALANCE} осколков")
                    )

    if user_data["credit_start_time"]:
        credit_start_time = datetime.fromisoformat(user_data["credit_start_time"])
        if now > credit_start_time + CREDIT_DURATION:
            if user_data["lives"] > 0:
                user_data["lives"] -= 1
                user_data["balance"] = 0
                user_data["balance"] += LIFE_POINTS
                user_data["credit_start_time"] = None
                asyncio.create_task(
                    send_and_delete_message(chat_id, f"{user_data['name']}, воспользовался зачарованием Маски Ткача [Где мой глаз?] и по нитям судьбы нашел лучшую точку выхода из Царства Теней. Найдено {LIFE_POINTS} осколков.")
                )
            else:
                user_data["jail_until"] = (now + JAIL_DURATION).isoformat()
                user_data["jail_count"] += 1
                user_data["credit_start_time"] = None
                asyncio.create_task(
                    send_and_delete_message(chat_id, f"Дорогой клиент {user_data['name']}, вы не успели расплатиться по долгам, поэтому пройдёмте в мою комфортабельный желу… тюрьму. Не бойтесь, через 2 часа вы будете свободны... Вас съел Чудесный Мимик.")
                )

    chat_user_balances[chat_id][user_id] = user_data
    save_data(chat_user_balances)

async def send_and_delete_message(chat_id: int, text: str):
    message = await bot.send_message(chat_id, text)
    await asyncio.sleep(DELET_TIME)
    await bot.delete_message(chat_id, message.message_id)

async def periodic_update():
    while True:
        now = datetime.now()
        for chat_id, users in chat_user_balances.items():
            for user_id, user_data in users.items():
                if user_data["jail_until"]:
                    jail_until = datetime.fromisoformat(user_data["jail_until"])
                    if now >= jail_until:
                        user_data["jail_until"] = None
                        user_data["balance"] = JAIL_BALANCE
                        await bot.send_message(chat_id, f"{user_data['name']}, сбежал из Царства Теней. Из жалости Дикие Тени дали вам {JAIL_BALANCE} осколков")
                
                if user_data["credit_start_time"]:
                    credit_start_time = datetime.fromisoformat(user_data["credit_start_time"])
                    if now > credit_start_time + CREDIT_DURATION:
                        if user_data["lives"] > 0:
                            user_data["lives"] -= 1
                            user_data["balance"] = 0
                            user_data["balance"] += LIFE_POINTS
                            user_data["credit_start_time"] = None
                            await bot.send_message(chat_id, f"{user_data['name']}, воспользовался зачарованием Маски Ткача [Где мой глаз?] и по нитям судьбы нашел лучшую точку выхода из Царства Теней. Найдено {LIFE_POINTS} осколков.")
                        else:
                            user_data["jail_until"] = (now + JAIL_DURATION).isoformat()
                            user_data["jail_count"] += 1
                            user_data["credit_start_time"] = None
                            await bot.send_message(chat_id, f"Дорогой клиент {user_data['name']}, вы не успели расплатиться по долгам, поэтому пройдёмте в мою комфортабельный желу… тюрьму. Не бойтесь, через 2 часа вы будете свободны... Вас съел Чудесный Мимик.")
        
        save_data(chat_user_balances)
        await asyncio.sleep(2)

def buy_life(chat_id: int, user_id: int):
    user_data = chat_user_balances[chat_id].get(user_id, {"balance": 0, "lives": 0})
    if user_data["balance"] >= LIFE_COST:
        user_data["balance"] -= LIFE_COST
        user_data["lives"] += 1
        chat_user_balances[chat_id][user_id] = user_data
        save_data(chat_user_balances)
        return True
    return False

def get_top_players(chat_id: int):
    if chat_id not in chat_user_balances:
        return []

    players = [
        {
            "user_id": user_id,
            "balance": data["balance"],
            "jail_count": data["jail_count"]
        }
        for user_id, data in chat_user_balances[chat_id].items()
    ]
    
    top_players = sorted(players, key=lambda x: (x["balance"], -x["jail_count"]), reverse=True)[:10]
    return top_players

@dp.message(Command('start'))
async def cmd_start(message: Message):
    await message.answer("Добро пожаловать в Блестящий Игорный дом! Введите /help для получения списка команд.")

@dp.message(Command('help'))
async def cmd_help(message: Message):
    await message.answer(
        "Этот бот начисляет баллы за выигрышные комбинации в слот-машине и штрафует за неудачные. "
        "Если ваш баланс уходит в минус, у вас есть 2 часа на восстановление положительного баланса. "
        "Если вы не успеете, вы будете отправлены в тюрьму на 1 час, и бот будет игнорировать ваши сообщения. "
        "Количество попаданий в тюрьму также фиксируется. Команда /balance покажет ваш текущий баланс и статус."
    )

@dp.message(Command('balance'))
async def cmd_balance(message: Message):
    chat_id = message.chat.id
    user_id = message.from_user.id
    user_data = chat_user_balances.get(chat_id, {}).get(user_id, {
        "balance": 0,
        "credit_start_time": None,
        "jail_until": None,
        "jail_count": 0,
        "lives": 0
    })
    balance = user_data["balance"]
    jail_count = user_data["jail_count"]
    jail_until = user_data["jail_until"]
    lives = user_data["lives"]
    
    now = datetime.now()
    jail_status = (
        f"в тюрьме до {jail_until}" 
        if jail_until and now < datetime.fromisoformat(jail_until) 
        else "не в тюрьме"
    )
    
    text=(f"Ваш текущий баланс: {balance} осколков.\nСтатус: {jail_status}.\nКоличество побегов из Царства Теней : {jail_count}.\nКоличество применений Маски Ткача : {lives}")
    await send_and_delete_message(chat_id, text)

@dp.message(Command('buy_life'))
async def cmd_buy_life(message: Message):
    chat_id = message.chat.id
    user_id = message.from_user.id
    if buy_life(chat_id, user_id):
        await message.answer(f"{message.from_user.full_name}, -{LIFE_COST} осколков. {chat_user_balances[chat_id][user_id]['lives']} возможностей применить Маску Ткача.")
    else:
        await message.answer(f"{message.from_user.full_name}, у вас недостаточно осколков для покупки.")

@dp.message(Command('top'))
async def cmd_top(message: Message):
    chat_id = message.chat.id
    top_players = get_top_players(chat_id)

    if not top_players:
        await message.answer("Пока нет данных о балансе пользователей в этом чате.")
        return

    response = "Топ-10 игроков в этом чате:\n"
    for i, player in enumerate(top_players, start=1):
        user = await bot.get_chat_member(chat_id, player["user_id"])
        response += f"{i}. {user.user.full_name} - Баланс: {player['balance']} осколков, Количество побегов из Царства Теней: {player['jail_count']}\n"
    
    await send_and_delete_message(chat_id, response)

@dp.message(F.dice)
async def handle_slot_machine_dice(message: Message):
    if message.forward_from:
        return

    user = message.from_user
    chat_id = message.chat.id
    user_id = message.from_user.id

    user_data = chat_user_balances.get(chat_id, {}).get(user_id, {
        "name": user.full_name,
        "balance": 0,
        "credit_start_time": None,
        "jail_until": None,
        "jail_count": 0,
        "games_played": [],
        "lives": 0
    })

    user_data["name"] = user.full_name

    now = datetime.now()
    user_data["games_played"] = [timestamp for timestamp in user_data["games_played"] if now - datetime.fromisoformat(timestamp) < TIME_LIMIT]

    if len(user_data["games_played"]) >= GAME_LIMIT:
        if message.dice.emoji == "🎰":
            await message.delete()
        return
    
    if user_data["jail_until"] and now < datetime.fromisoformat(user_data["jail_until"]):
        await message.delete()
        return

    if message.dice.emoji == "🎰":
        dice_value = message.dice.value

        if dice_value == 64:
            update_balance(chat_id, user_id, JACKPOT)
            await send_and_delete_message(chat_id, f"{user.full_name}, поздравляем! Три семерки! 🎉 Джекпот! Вы получили {JACKPOT} монет Ноктиса.")
        elif dice_value in [1, 22, 43]:
            update_balance(chat_id, user_id, WIN)
            await send_and_delete_message(chat_id, f"{user.full_name}, вы выиграли! Вы получили {WIN} монет Ноктиса.")
        else:
            update_balance(chat_id, user_id, LOOSE)
            await send_and_delete_message(chat_id, f"{user.full_name}, Результат: {dice_value}. Неудача! Вы потеряли {LOOSE} осколков.")

async def main():
    asyncio.create_task(periodic_update())
    await dp.start_polling(bot)

if __name__ == '__main__':
    asyncio.run(main())
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
