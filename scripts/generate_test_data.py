import os
import json
import random
import time


SERVERS = [8001, 8002, 8004, 8024, 9001, 8010]
SOURCE_TYPES = [1, 2, 3, 4, 5, 6, 7, 8]

# Realistic ID pools based on current UI mappings
PET_IDS = [
    1001,1002,1003,1004,1005,1006,1007,1008,1009,1010,1011,1012,1013,1014,1015,1016,
    2001,2002,2003,2004,2005,2006,2007,2008,2009,2010,2011,2012,2013,2014,2015,2017,
    3001,3002,3003,3004,3005,3006,3007,3008,3009,3010,3011,3012,30120,3013,3014,3015,3016,3017,3018,
    4001,4002,4003,4004,4005,4006,4007,
    5001,5002,5003,5004,5005,5006,5007,5008
]

RUNE_IDS = [
    26001,26002,26003,26006,26007,26008,26009,26010,26011,26012,26013
]

ARMOR_IDS = [
    340001,340002,340101,340111,340003,340004,340005,
    340121,340131,340141,340151,340201,
    340161,340171,340181,340191,340241,340251,340261,340281,
    340210,340220,340230,340270,340290,
    340330,340340,340350,340360,
    340430,340440
]


def random_record(now_ts: int) -> dict:
    # 时间分布：近30天任意秒
    server = random.choice(SERVERS)
    ts = now_ts - random.randint(0, 30*24*3600)
    # 等级：30~100 更接近实际
    level = random.randint(30, 100)
    clazz = random.randint(1, 11)
    schools = random.randint(0, 2)
    opp_c = random.randint(1, 11)
    opp_s = random.randint(0, 2)
    is_win = random.randint(0, 1)
    duration = random.randint(20, 600)

    # 宠物：0~3 个；天赋与宠物等长；部分样本天赋=0（表示全部）
    k_pet = random.randint(0, 3)
    spirit_animal = random.sample(PET_IDS, k_pet)
    spirit_animal_talents = []
    for _ in range(k_pet):
        if random.random() < 0.2:
            spirit_animal_talents.append(0)
        else:
            spirit_animal_talents.append(random.randint(1, 5))

    # 传说符文：0~3 个
    legendary_runes = random.sample(RUNE_IDS, random.randint(0, 3))

    # 超能战甲：10% 为空
    super_armor = random.choice(ARMOR_IDS) if random.random() > 0.1 else None

    # 来源：均匀分布
    source_type = random.choice(SOURCE_TYPES)

    return {
        "server": server,
        "timestamp": ts,
        "level": level,
        "class": clazz,
        "schools": schools,
        "opponent_class": opp_c,
        "opponent_schools": opp_s,
        "is_win": is_win,
        "duration": duration,
        "spirit_animal": spirit_animal,
        "spirit_animal_talents": spirit_animal_talents,
        "legendary_runes": legendary_runes,
        "super_armor": super_armor,
        "source_type": source_type,
    }


def main():
    out_dir = os.path.join(os.getcwd(), 'data_logs')
    os.makedirs(out_dir, exist_ok=True)
    now = int(time.time())
    total = 8000
    out_path = os.path.join(out_dir, 'sample.jsonl')
    with open(out_path, 'w', encoding='utf-8') as fp:
        for _ in range(total):
            rec = random_record(now)
            fp.write(json.dumps(rec, ensure_ascii=False) + '\n')
    print(f"Generated {total} records at {out_path}")


if __name__ == '__main__':
    main()


