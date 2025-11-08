#!/bin/bash

# --- Интерактивный и безопасный скрипт для создания RAID-массива ---

# Проверка, запущен ли скрипт от имени root
if [ "$EUID" -ne 0 ]; then
  echo "Ошибка: Пожалуйста, запустите этот скрипт с правами суперпользователя (sudo)."
  exit 1
fi

# Проверка наличия mdadm
if ! command -v mdadm &> /dev/null; then
  echo "Ошибка: Утилита mdadm не найдена. Установите ее (например, 'sudo apt install mdadm' или 'sudo yum install mdadm')."
  exit 1
fi

echo "--- Создание нового RAID-массива ---"
echo -e "\n\033[1;33mВНИМАНИЕ: Следующие шаги приведут к ПОЛНОМУ УДАЛЕНИЮ ВСЕХ ДАННЫХ на выбранных дисках.\033[0m"
echo "Убедитесь, что вы выбрали правильные диски и сделали резервные копии."
echo "-------------------------------------------"

# Получаем и выводим список доступных блочных устройств (дисков) без разделов и не смонтированных
mapfile -t ALL_DISKS < <(lsblk -dno NAME,SIZE,TYPE | grep 'disk' | awk '{print "/dev/"$1, $2}')
AVAILABLE_DISKS=()
echo "Доступные диски для создания RAID:"
i=0
for disk_info in "${ALL_DISKS[@]}"; do
    disk_path=$(echo "$disk_info" | awk '{print $1}')
    # Проверяем, не является ли диск частью существующего RAID или LVM, и не смонтирован ли он
    if ! lsblk -no MOUNTPOINT "$disk_path" | grep -q / && ! mdadm --examine "$disk_path" &>/dev/null; then
        AVAILABLE_DISKS+=("$disk_path")
        echo "  $i: $disk_info"
        ((i++))
    fi
done

if [ ${#AVAILABLE_DISKS[@]} -eq 0 ]; then
    echo "Не найдено свободных дисков для создания массива."
    exit 1
fi

# Выбор дисков пользователем
echo -e "\nВведите номера дисков для массива через пробел (например: 0 1 2 3):"
read -r -a selected_indices
USER_DEVICES=()
for index in "${selected_indices[@]}"; do
    if [[ "$index" =~ ^[0-9]+$ ]] && [ "$index" -lt "${#AVAILABLE_DISKS[@]}" ]; then
        USER_DEVICES+=("${AVAILABLE_DISKS[$index]}")
    else
        echo "Ошибка: неверный номер диска '$index'."
        exit 1
    fi
done

NUM_DEVICES=${#USER_DEVICES[@]}
DEVICES_STR="${USER_DEVICES[*]}"
echo "Выбраны диски: $DEVICES_STR ($NUM_DEVICES шт.)"

# Выбор уровня RAID с рекомендациями
echo -e "\nВыберите уровень RAID:"
echo "  [1] RAID 1 (Зеркало, мин. 2 диска) - Рекомендация: высокая надежность, для ОС или важных данных."
echo "  [5] RAID 5 (Четность, мин. 3 диска) - Рекомендация: хороший баланс скорости, объема и надежности."
echo "  [6] RAID 6 (Двойная четность, мин. 4 диска) - Рекомендация: очень высокая надежность, для критически важных архивов."
echo "  [10] RAID 10 (Зеркало+Страйп, мин. 4 диска, четное число) - Рекомендация: максимальная производительность и высокая надежность."
read -p "Ваш выбор [1, 5, 6, 10]: " raid_choice

case $raid_choice in
    1) RAID_LEVEL=1; min_disks=2 ;;
    5) RAID_LEVEL=5; min_disks=3 ;;
    6) RAID_LEVEL=6; min_disks=4 ;;
    10) RAID_LEVEL=10; min_disks=4 ;;
    *) echo "Неверный выбор."; exit 1 ;;
esac

# Проверка количества дисков
if [ "$NUM_DEVICES" -lt "$min_disks" ]; then
    echo "Ошибка: для RAID $RAID_LEVEL требуется минимум $min_disks диска(ов), а выбрано $NUM_DEVICES."
    exit 1
fi
if [ "$RAID_LEVEL" -eq 10 ] && [ $((NUM_DEVICES % 2)) -ne 0 ]; then
    echo "Ошибка: для RAID 10 требуется четное количество дисков."
    exit 1
fi

# Имя устройства RAID
RAID_DEVICE="/dev/md0"
if [ -e "$RAID_DEVICE" ]; then
    RAID_DEVICE="/dev/md/MyArray" # Альтернативный путь, если md0 занят
fi
echo "Массив будет создан как $RAID_DEVICE"


# ФИНАЛЬНОЕ ПОДТВЕРЖДЕНИЕ
echo -e "\n\033[1;31m!!! ПОСЛЕДНЕЕ ПРЕДУПРЕЖДЕНИЕ !!!\033[0m"
echo "Вы собираетесь создать RAID $RAID_LEVEL на устройстве $RAID_DEVICE из дисков: $DEVICES_STR"
echo -e "Все данные на этих дисках будут \033[1;31mБЕЗВОЗВРАТНО УНИЧТОЖЕНЫ\033[0m."
read -p "Для подтверждения введите 'YES' (в верхнем регистре): " confirmation

if [ "$confirmation" != "YES" ]; then
    echo "Операция отменена пользователем."
    exit 0
fi

# 1. Зануление суперблоков
echo -e "\nШаг 1: Зануление суперблоков на выбранных дисках..."
mdadm --zero-superblock --force ${DEVICES_STR}
echo "Суперблоки очищены."

# 2. Создание RAID-массива
echo -e "\nШаг 2: Создание массива RAID $RAID_LEVEL..."
mdadm --create --verbose ${RAID_DEVICE} --level=${RAID_LEVEL} --raid-devices=${NUM_DEVICES} ${DEVICES_STR}
echo "Команда на создание массива отправлена. Процесс синхронизации запущен в фоновом режиме."

# 3. Сохранение конфигурации
echo -e "\nШаг 3: Сохранение конфигурации для автоматической сборки при загрузке..."
# Убедимся, что директория существует
mkdir -p /etc/mdadm
# Добавляем новую конфигурацию в файл
mdadm --detail --scan >> /etc/mdadm/mdadm.conf
echo "Конфигурация сохранена в /etc/mdadm/mdadm.conf"

echo -e "\n--- Массив создан. Теперь вы можете проверить его статус ---"
sleep 2

# 4. Вывод команд для проверки с описанием
echo -e "\n\033[1;32m=== Команды для проверки статуса массива ===\033[0m"

echo -e "\n\033[1m1. Краткий статус (cat /proc/mdstat):\033[0m"
cat /proc/mdstat
echo -e "\n\033[1mЧто означают значения в 'cat /proc/mdstat':\033[0m"
echo "  - \`md0 : active raid6 sde[4] sdd[3] sdc[2] sdb[1]\`: Имя массива, его статус, уровень RAID и диски в его составе."
echo "  - \`blocks [UUUU]\` или \`[UU_U]\`: Статус дисков. \`U\` (Up) - диск работает нормально. \`_\` (underscore) - диск отказал или отсутствует."
echo "  - \`[=>........]\`: Индикатор процесса синхронизации/ребилда. Показывает, на сколько процентов завершена операция."
echo "  - \`resync\`, \`recovery\`, \`check\`: Текущая операция, выполняемая над массивом."

echo -e "\n\033[1m2. Детальный статус (mdadm --detail ${RAID_DEVICE}):\033[0m"
mdadm --detail ${RAID_DEVICE}
echo -e "\n\033[1mЧто означают ключевые поля в 'mdadm --detail':\033[0m"
echo "  - \`Version\`, \`Creation Time\`: Информация о метаданных и времени создания."
echo "  - \`Raid Level\`, \`Array Size\`: Уровень и полезный объем массива (без учета дисков под четность)."
echo "  - \`Used Dev Size\`: Размер, используемый на каждом из дисков."
echo "  - \`Raid Devices\`: Общее количество дисков, выделенных под массив."
echo "  - \`Total Devices\`: Общее количество дисков в
