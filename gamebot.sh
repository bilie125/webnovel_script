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
import json
import os
import logging
from datetime import datetime, timedelta
from collections import deque

from aiogram import Bot, Dispatcher, F
from aiogram.types import Message, ContentType
from aiogram.exceptions import TelegramBadRequest
from aiogram.filters import Command

# Конфигурация
API_TOKEN = 'bot_api'
BASE_BALANCE = 1000
JACKPOT = 2000
WIN = 1000
LOSS = 200
LIFE_BALANCE = 2000
LIFE_PRICE = 1500
FORWARDED_CASINO_PENALTY = 1000
JAIL_DURATION = timedelta(hours=1)
NEGATIVE_THRESHOLD_DURATION = timedelta(hours=2)
PLAY_COOLDOWN = timedelta(hours=1)
USERS_FILE = 'users.json'
MAX_CONSECUTIVE_MESSAGES = 3
ADMIN_IDS = [6273910889, 507583454, 6787450546, 684795841, 5055660788, 1408061454, 418190922, 1133387699, 5345361232, 6962389672, 1951350054, 8141866475 ]

# Настройка логирования
logging.basicConfig(level=logging.INFO)

# Инициализация бота и диспетчера
bot = Bot(token=API_TOKEN)
dp = Dispatcher()

# Глобальная переменная для данных пользователей.
# Структура: {"users": {user_id (str): { ... данные пользователя ... }}}
users = {}

# Эфемерное хранение для отслеживания последовательных сообщений
user_messages = {}

# Загрузка данных пользователей из файла
async def load_users():
    global users
    if os.path.exists(USERS_FILE):
        try:
            with open(USERS_FILE, 'r', encoding='utf-8') as f:
                users = json.load(f)
                if "users" not in users:
                    users["users"] = {}
        except Exception as e:
            logging.error(f"Ошибка загрузки данных пользователей: {e}")
            users = {"users": {}}
    else:
        users = {"users": {}}

# Сохранение данных пользователей в файл
async def save_users():
    try:
        with open(USERS_FILE, 'w', encoding='utf-8') as f:
            json.dump(users, f, ensure_ascii=False, indent=4)
    except Exception as e:
        logging.error(f"Ошибка сохранения данных пользователей: {e}")

# Получение данных пользователя (инициализация, если не существует)
def get_user(user_id: int) -> dict:
    uid = str(user_id)
    if uid not in users["users"]:
        users["users"][uid] = {
            "balance": BASE_BALANCE,
            "last_play": None,
            "negative_since": None,
            "in_jail": False,
            "jail_until": None,
            "lives": 0,
            "first_name": "",
            "last_name": "",
            "username": ""
        }
    return users["users"][uid]

# Обновление данных пользователя и сохранение
async def update_user(user_id: int, data: dict):
    users["users"][str(user_id)] = data
    await save_users()

# Функция для удаления сообщения (с задержкой или мгновенно)
async def safe_delete_message(chat_id: int, message_id: int, delay: int = 40, immediate: bool = False):
    if immediate:
        try:
            await bot.delete_message(chat_id, message_id)
        except TelegramBadRequest:
            pass
        except Exception as e:
            logging.error(f"Ошибка удаления сообщения: {e}")
    else:
        await asyncio.sleep(delay)
        try:
            await bot.delete_message(chat_id, message_id)
        except TelegramBadRequest:
            pass
        except Exception as e:
            logging.error(f"Ошибка удаления сообщения: {e}")

# Функция для проверки статуса тюрьмы
def check_jail_status(user: dict, now: datetime) -> str:
    if user.get("in_jail"):
        jail_until = user.get("jail_until")
        if jail_until:
            try:
                jail_until_dt = datetime.fromisoformat(jail_until)
                if now >= jail_until_dt:
                    # Освобождаем пользователя из тюрьмы
                    user["in_jail"] = False
                    user["balance"] = BASE_BALANCE
                    user["negative_since"] = None
                    user["jail_until"] = None
                    return "Вы освобождены из тюрьмы! Ваш баланс восстановлен."
                else:
                    return "Вы находитесь в тюрьме и не можете играть."
            except (ValueError, TypeError):
                logging.error(f"Ошибка преобразования даты jail_until: {jail_until}")
    return ""

# Команда для отображения топ-10 игроков
@dp.message(Command(commands=["top"]))
async def show_top_10(message: Message):
    data = users
    if "users" not in data or not data["users"]:
        reply = await message.answer("Список пользователей пуст.")
        asyncio.create_task(safe_delete_message(message.chat.id, reply.message_id))
        return

    sorted_users = sorted(data["users"].values(), key=lambda x: x["balance"], reverse=True)
    top_10_text = "🏆 Топ-10 игроков:\n"
    for idx, user in enumerate(sorted_users[:10], start=1):
        # Используем полное имя: если есть first_name и last_name, то объединяем их, иначе, если есть username, используем его
        full_name = f"{user.get('first_name', '')} {user.get('last_name', '')}".strip()
        if full_name:
            name = full_name
        elif user.get("username"):
            name = f"@{user['username']}"
        else:
            name = "Аноним"
        top_10_text += f"{idx}. {name} — {user['balance']} баллов\n"
    reply = await message.answer(top_10_text)
    asyncio.create_task(safe_delete_message(message.chat.id, reply.message_id))

# Обработка броска кубика (Dice) с эмодзи 🎰
@dp.message(F.content_type == ContentType.DICE)
async def process_dice(message: Message):
    if message.dice.emoji != '🎰':
        return

    # Если сообщение пересланное, не запускаем игру, а добавляем штраф
    if message.forward_date is not None:
        user = get_user(message.from_user.id)
        user["balance"] -= FORWARDED_CASINO_PENALTY
        await update_user(message.from_user.id, user)
        await message.answer(f"{message.from_user.full_name}, пересланные стикеры казино запрещены! Вам снято {FORWARDED_CASINO_PENALTY} монет в качестве наказания.")
        asyncio.create_task(safe_delete_message(message.chat.id, message.message_id, immediate=True))
        return

    user = get_user(message.from_user.id)
    # Обновляем данные о пользователе
    user["first_name"] = message.from_user.first_name
    user["last_name"] = message.from_user.last_name if message.from_user.last_name else ""
    user["username"] = message.from_user.username if message.from_user.username else ""

    now = datetime.now()
    jail_status = check_jail_status(user, now)
    if jail_status:
        await message.answer(jail_status)
        await safe_delete_message(message.chat.id, message.message_id, immediate=True)
        await update_user(message.from_user.id, user)
        return

    if user.get("last_play") and now - datetime.fromisoformat(user["last_play"]) < PLAY_COOLDOWN:
        await safe_delete_message(message.chat.id, message.message_id, immediate=True)
        return
    user["last_play"] = now.isoformat()

    dice_value = message.dice.value
    result_text = ""
    if dice_value == 64:
        user["balance"] += JACKPOT
        result_text = f"💰 {message.from_user.full_name} Джекпот! Вы выиграли {JACKPOT} монет!"
    elif dice_value in (1, 22, 43):
        user["balance"] += WIN
        result_text = f"💵 {message.from_user.full_name} Выигрыш! Вы получили {WIN} монет."
    else:
        user["balance"] -= LOSS
        result_text = f"😞 {message.from_user.full_name} Проигрыш. С вашего счета снято {LOSS} монет."
        asyncio.create_task(safe_delete_message(message.chat.id, message.message_id))
    
    if user["balance"] < 0:
        if not user.get("negative_since"):
            user["negative_since"] = now.isoformat()
        elif now - datetime.fromisoformat(user["negative_since"]) >= NEGATIVE_THRESHOLD_DURATION:
            if user.get("lives", 0) > 0:
                user["lives"] -= 1
                user["balance"] = LIFE_BALANCE
                user["negative_since"] = None
                result_text += "\n✅ Жизнь использована, баланс восстановлен, тюрьма предотвращена!"
            else:
                user["in_jail"] = True
                user["jail_until"] = (now + JAIL_DURATION).isoformat()
                result_text += "\n🚨 Вы отправлены в тюрьму на 1 час за отрицательный баланс!"

    await update_user(message.from_user.id, user)
    result_msg = await message.answer(result_text)
    # Удаляем результат через 40 секунд, если он не содержит символы выигрыша
    if "💰" not in result_text and "💵" not in result_text:
        asyncio.create_task(safe_delete_message(result_msg.chat.id, result_msg.message_id))

# Команда для проверки баланса
@dp.message(Command(commands=["balance"]))
async def cmd_balance(message: Message):
    user = get_user(message.from_user.id)
    balance_msg = f"Ваш текущий баланс: {user['balance']} баллов."
    msg = await message.answer(balance_msg)
    asyncio.create_task(safe_delete_message(message.chat.id, message.message_id))
    asyncio.create_task(safe_delete_message(msg.chat.id, msg.message_id))

# Команда справедливости (justice)
@dp.message(Command(commands=["justice"]))
async def justice_handler(message: Message):
    if message.from_user.id not in ADMIN_IDS:
        reply = await message.reply("Эта команда доступна только администраторам!")
        asyncio.create_task(safe_delete_message(message.chat.id, reply.message_id))
        return

    if not message.reply_to_message:
        reply = await message.reply("Эта команда должна быть ответом на сообщение пользователя!")
        asyncio.create_task(safe_delete_message(message.chat.id, reply.message_id))
        return

    dice_message = await message.reply_dice(emoji="🎲")
    dice_value = dice_message.dice.value
    target_user_name = message.reply_to_message.from_user.full_name
    if dice_value == 6:
        result_text = f"Решением районного суда города ОССК {target_user_name} признан невиновным"
    else:
        result_text = (f"Решением районного суда города ОССК {target_user_name} признан виновным в нарушении правил чата. "
                       f"Приговаривается к заключению на срок {dice_value} {get_days_suffix(dice_value)}.")
    await message.reply(result_text)
    

# Функция для определения правильного окончания слова "день"
def get_days_suffix(days):
    if 11 <= days % 100 <= 19:
        return "дней"
    last_digit = days % 10
    if last_digit == 1:
        return "день"
    elif 2 <= last_digit <= 4:
        return "дня"
    else:
        return "дней"

# Команда для покупки жизни
@dp.message(Command(commands=["buy_life"]))
async def cmd_buy_life(message: Message):
    user = get_user(message.from_user.id)
    if user["balance"] < LIFE_PRICE:
        response = f"У вас недостаточно баллов для покупки жизни. Стоимость {LIFE_PRICE}"
    else:
        user["balance"] -= LIFE_PRICE
        user["lives"] = user.get("lives", 0) + 1
        response = "Вы успешно купили жизнь!"
    await update_user(message.from_user.id, user)
    msg = await message.answer(response)
    asyncio.create_task(safe_delete_message(message.chat.id, message.message_id))
    asyncio.create_task(safe_delete_message(msg.chat.id, msg.message_id))


# Новая реализация отслеживания подряд одинаковых сообщений
def track_and_check_user_messages(user_id: int, message_text: str) -> bool:
    if user_id not in user_messages:
        user_messages[user_id] = {"last": None, "count": 0}
    data = user_messages[user_id]
    if message_text == data["last"]:
        data["count"] += 1
    else:
        data["last"] = message_text
        data["count"] = 1
    return data["count"] >= 3

# Универсальный обработчик сообщений (текст, стикеры, анимации, видео, фото)
@dp.message(F.content_type.in_([ContentType.TEXT, ContentType.STICKER, ContentType.ANIMATION, ContentType.VIDEO, ContentType.PHOTO]))
async def handle_all_messages(message: Message):
    # Если сообщение является частью медиагруппы, не учитываем его отдельно
    if message.media_group_id:
        return
    content = message.text or message.caption or ''
    if track_and_check_user_messages(message.from_user.id, content):
        await safe_delete_message(message.chat.id, message.message_id, immediate=True)

# Универсальный обработчик для удаления команд, отправленных пользователями
@dp.message(lambda m: m.text and m.text.startswith('/'))
async def delete_command_messages(message: Message):
    # Удаляем команду через 40 секунд
    await safe_delete_message(message.chat.id, message.message_id, delay=5)



# Главная функция для запуска бота
async def main():
    await load_users()
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
