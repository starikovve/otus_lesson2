# otus_lesson2
Administrator Linux. Professional
Домашнее задание: работа с mdadm по курсу «Администратор Linux. Professional»

Задание
Добавить в виртуальную машину несколько дисков

Собрать RAID-0/1/5/10 на выбор

Сломать и починить RAID

Создать GPT таблицу, пять разделов и смонтировать их в системе.

Ход выполнения:

На проверку отправьте:

скрипт для создания рейда https://github.com/starikovve/otus_lesson2/blob/main/create_raid_mdadm.sh

отчет по командам для починки RAID и созданию разделов

Отчет по командам
Шаги по имитации сбоя и починке RAID, а также по созданию разделов и их монтированию.

Моделирование сбоя и починка RAID-массива


Для имитации сбоя диска `/dev/sde` используется команда `mdadm --fail`. Это помечает диск как сбойный в массиве.

mdadm /dev/md0 --fail /dev/sde

 <img width="908" height="245" alt="image" src="https://github.com/user-attachments/assets/16764be4-9ca6-47c0-9fc0-fc89fca637a0" />


Проверка состояния массива после сбоя
После выполнения команды выше, массив переходит в деградированное состояние. Это можно увидеть в выводе cat /proc/mdstat (диск помечен как (F)) и mdadm -D /dev/md0 (статус faulty).

<img width="964" height="175" alt="image" src="https://github.com/user-attachments/assets/b0d73b72-11b4-4abf-b45e-61813756ef11" />
  
mdadm -D /dev/md0

<img width="974" height="854" alt="image" src="https://github.com/user-attachments/assets/dc8a6ab2-7ae3-4240-9852-4b84b6fb0dd4" />


Удаление сбойного диска из массива
Физически "извлекаем" сбойный диск из конфигурации RAID.
mdadm /dev/md0 --remove /dev/sde

 <img width="974" height="844" alt="image" src="https://github.com/user-attachments/assets/5bbd8dd7-32ad-4443-9d9a-bcd5b9ac745b" />



Добавление "нового" диска и восстановление
Представляем, что мы вставили новый исправный диск (в нашем случае используем тот же /dev/sde) и добавляем его обратно в массив.
mdadm /dev/md0 --add /dev/sde
Сразу после добавления диска массив начнет процесс восстановления (rebuild), копируя необходимые данные и восстанавливая избыточность. За процессом можно наблюдать с помощью команд cat /proc/mdstat и mdadm -D /dev/md0, где диск будет иметь статус spare rebuilding.

 <img width="900" height="169" alt="image" src="https://github.com/user-attachments/assets/71242fbe-bb55-4ef3-8d23-e4e4d0d02f5f" />


Создание разделов, файловых систем и монтирование
После того как RAID-массив собран и исправен, на нем можно создавать разделы.
Создание таблицы разделов GPT
Создаем на нашем RAID-устройстве /dev/md0 современную таблицу разделов GPT. Ключ -s выполняет команду в неинтерактивном режиме.
parted -s /dev/md0 mklabel gpt

<img width="947" height="67" alt="image" src="https://github.com/user-attachments/assets/e52154c2-697e-4027-888e-55874fcfd8c2" />

 
Создание четырх разделов
С помощью parted создаем пять разделов, каждый из которых занимает 25% от общего объема диска.
parted /dev/md0 mkpart primary ext4 0% 25%
parted /dev/md0 mkpart primary ext4 25% 50%
parted /dev/md0 mkpart primary ext4 50% 75%
parted /dev/md0 mkpart primary ext4 75% 100%

<img width="589" height="630" alt="image" src="https://github.com/user-attachments/assets/885f9767-a6b2-4a88-a161-ddc00b03226d" />
 

Создание файловых систем
Форматируем каждый созданный раздел в файловую систему ext4. Для этого используем цикл.
for i in $(seq 1 4); do mkfs.ext4 /dev/md0p$i; done
Проверяем 
lsblk -f

<img width="974" height="507" alt="image" src="https://github.com/user-attachments/assets/2932d25a-68b0-436b-ae89-3794276ebebf" />
 
Монтирование разделов
Создаем директории, которые будут служить точками монтирования, и монтируем в них наши разделы.
Создаем каталоги
mkdir -p /raid/part{1,2,3,4}

<img width="657" height="139" alt="image" src="https://github.com/user-attachments/assets/fbbfd86c-b43c-4e1b-a411-4943dd262430" />
 

# Монтируем разделы в соответствующие каталоги
for i in $(seq 1 4); do mount /dev/md0p$i /raid/part$i; done


Проверка результата
Убедиться, что все разделы успешно смонтированы, можно с помощью команды df или lsblk.
 
<img width="827" height="330" alt="image" src="https://github.com/user-attachments/assets/375684c5-23aa-4563-b5c9-5636d071cb37" />

<img width="767" height="316" alt="image" src="https://github.com/user-attachments/assets/86150804-a319-4b3c-90d2-6e17d05665f5" />

 
