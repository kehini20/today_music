# TDM Parser Test Samples

빠른 붙여넣기 / 셋리스트 파서 수정 시 회귀 테스트용 샘플입니다.

목표:

* 정상적인 `가수 - 곡명` 입력을 망가뜨리지 않는다.
* 셋리스트 헤더/행사명/해시태그/이모지는 곡 후보로 넣지 않는다.
* 추정 가수명이 있는 경우 곡명-only 줄을 안정적으로 처리한다.
* 애매한 케이스는 무리하게 자동 처리하기보다 확인 필요로 보내는 것이 안전하다.

---

## 1. 일반 `가수 - 곡명` 대량 입력

### 입력

```text
강진 - 땡벌
영탁 - 니가 왜 거기서 나와
홍진영 - 사랑의 배터리
나훈아 - 비 내리는 호남선
조영남 - 화개장터
영탁 - 막걸리 한잔
윤수일 - 아파트
로제, Bruno Mars - APT.
거북이 - 빙고
Ylvis - The Fox(What Does the Fox Say?)
크라잉넛 - 비둘기
크라잉넛 - 말달리자
이적 - 하늘을 달리다
10cm - 폰서트
MONGOL800 - 작은 사랑의 노래
Ado - 나는 최강
Vaundy - 주름 맞추기
Hump Back - 친애하는 소년이여
Naomi Scott - Speechless (알라딘 ost)
즛토마요 - 초침을 깨물다
어쿠스틱 콜라보 - 묘해, 너와
```

### 기대 결과

각 줄을 `가수명 / 곡명`으로 정상 분리한다.

특히 아래 케이스가 깨지면 안 된다.

```text
로제, Bruno Mars / APT.
10cm / 폰서트
Ylvis / The Fox(What Does the Fox Say?)
Naomi Scott / Speechless (알라딘 ost)
```

---

## 2. 기본 뮤지컬/공연 `가수 - 곡명` 입력

### 입력

```text
마마돈크라이 - 달콤한 꿈
곤투모로우 - 저 바다에 날
넥스트투노멀 - 암얼랍
노트르담드파리 - 대성당들의 시대
배니싱 - 햇빛 속으로
```

### 기대 결과

```text
마마돈크라이 / 달콤한 꿈
곤투모로우 / 저 바다에 날
넥스트투노멀 / 암얼랍
노트르담드파리 / 대성당들의 시대
배니싱 / 햇빛 속으로
```

---

## 3. 대괄호 한글명 / 영문명 헤더

### 입력

```text
[카디 / KARDI💖🔥]

뷰민라 2026 셋리스트📃

WatchOut
Riot
Player 1
```

### 기대 결과

```text
추정 가수명: 카디

카디 / WatchOut
카디 / Riot
카디 / Player 1
```

### 주의

`[카디 / KARDI💖🔥]`는 가수명 추정에만 사용하고, 곡 후보로 들어가면 안 된다.

---

## 4. 공연명 키워드 앞 가수명

### 입력

```text
260530 can't be blue SNIPPET CONCERT | May be blue
셋리스트💙

Intro+can't love
Commercial love
상사화
```

### 기대 결과

```text
추정 가수명: can't be blue

can't be blue / Intro+can't love
can't be blue / Commercial love
can't be blue / 상사화
```

### 주의

`셋리스트💙`는 메타 줄로 제외한다.
이모지 `💙`가 가수명으로 잡히면 안 된다.

---

## 5. 마지막 해시태그 가수명

### 입력

```text
260529 일산호수공원 버스킹 셋리스트

1. Teenage Blue
2. Left or Right
3. 라일라(LAILA)
4. SOMEBODY HELP ME

#하이파이유니콘
```

### 기대 결과

```text
추정 가수명: 하이파이유니콘

하이파이유니콘 / Teenage Blue
하이파이유니콘 / Left or Right
하이파이유니콘 / 라일라(LAILA)
하이파이유니콘 / SOMEBODY HELP ME
```

### 주의

`#하이파이유니콘`은 가수명 추정에만 사용하고, 곡 후보로 들어가면 안 된다.

---

## 6. 셋리스트 앞 해시태그 가수명

### 입력

```text
260606 BELLEFORET WEEK: My Volume 벨포레위크 #까치산 셋리스트
1. INTRO + 다이얼
2. INTRO + RESCUE!
3. INTRO + 표정이나 가면 따위
```

### 기대 결과

```text
추정 가수명: 까치산

까치산 / INTRO + 다이얼
까치산 / INTRO + RESCUE!
까치산 / INTRO + 표정이나 가면 따위
```

### 주의

`My Volume`이나 `BELLEFORET WEEK`를 가수명으로 잡으면 안 된다.

---

## 7. 헤더 안의 해시태그 가수명

### 입력

```text
무주산골영화제 #최유리

생각을 멈추다 보면
동그라미
바람
연못
노력
세상이 동화처럼
밤 - 바다
```

### 기대 결과

```text
추정 가수명: 최유리

최유리 / 생각을 멈추다 보면
최유리 / 동그라미
최유리 / 바람
최유리 / 연못
최유리 / 노력
최유리 / 세상이 동화처럼
최유리 / 밤 - 바다
```

### 주의

추정 가수명이 있는 상태에서는 `밤 - 바다`를 가수/곡명으로 쪼개지 말고 곡명 전체로 유지한다.

---

## 8. 날짜 + 가수명 + 행사명

### 입력

```text
260605 윤마치 MRCH
2026 Road to BU-ROCK 로드투부락
셋리스트

나쁜영원
Lovers
불안나무
아직은낭만
마치무드
항복
Peachy
```

### 기대 결과

```text
추정 가수명: 윤마치 MRCH

윤마치 MRCH / 나쁜영원
윤마치 MRCH / Lovers
윤마치 MRCH / 불안나무
윤마치 MRCH / 아직은낭만
윤마치 MRCH / 마치무드
윤마치 MRCH / 항복
윤마치 MRCH / Peachy
```

### 주의

`2026 Road to BU-ROCK 로드투부락`은 행사명/메타 줄로 보고 곡 후보에서 제외한다.

---

## 9. 외국어/한자 가수명

### 입력

```text
260601 《魁》 런던 공연 셋리스트

1. 魁
2. Saturday Night
3. Losing My Mind
4. kiss
5. Dancing Till I Die
```

### 기대 결과

```text
추정 가수명: 魁

魁 / 魁
魁 / Saturday Night
魁 / Losing My Mind
魁 / kiss
魁 / Dancing Till I Die
```

---

## 10. 공연명 키워드 뒤 가수명

### 입력

```text
260531 BUSKING CONCERT 김태우 with Friends 셋리스트

사랑비
둘이면
한구석에
Friday Night
Just The Two Of Us (with. Tim)
길 (with. 이영현, Tim)
촛불하나 (with. 이영현, Tim)
```

### 기대 결과

```text
추정 가수명: 김태우

김태우 / 사랑비
김태우 / 둘이면
김태우 / 한구석에
김태우 / Friday Night
김태우 / Just The Two Of Us (with. Tim)
김태우 / 길 (with. 이영현, Tim)
김태우 / 촛불하나 (with. 이영현, Tim)
```

### 주의

`with. Tim`, `with. 이영현, Tim`은 곡명 일부로 유지한다.

---

## 11. 곡명 - 출연자명

### 입력

```text
1. Proud of your boy - 차윤해
2. Come what may - 최지혜&차윤해
3. 놈의 마음속으로 - 차윤해&김성식
```

### 기대 결과

```text
차윤해 / Proud of your boy
최지혜&차윤해 / Come what may
차윤해&김성식 / 놈의 마음속으로
```

### 주의

이 케이스는 예외 처리다.
일반적인 `가수 - 곡명` 케이스를 망가뜨리면 안 된다.

---

## 12. #숫자 + 가수 - 곡명

### 입력

```text
[⚔️🍀용사님의 듀엣모험 셋리스트🧭🌊]
#1 AKMU(악뮤) - Crescendo(크레셴도)
#2 안예은 - 상사화
#3 안예은 - 능소화
```

### 기대 결과

```text
추정 가수명: 비어 있음

AKMU(악뮤) / Crescendo(크레셴도)
안예은 / 상사화
안예은 / 능소화
```

### 주의

`[⚔️🍀용사님의 듀엣모험 셋리스트🧭🌊]`는 메타 헤더로 보고 가수명 후보와 곡 후보에서 제외한다.

`#1`, `#2`, `#3`은 순번으로 제거한다.

단, `#1` 단독 줄이나 `#1 Song`처럼 가수-곡명 구조가 아닌 경우는 곡명일 수 있으므로 함부로 지우지 않는다.

---

## 13. 합동 공연 / 곡별 담당자 표기

### 입력

```text
시네마송콘 진태화 한보라 셋리스트
1. 그게 나의 전부란 걸(번지점프를 하다) - 듀엣
2. 봄날은 간다(봄날은 간다 OST) - 한보라
3. City of stars(라라랜드 OST) - 진태화
4. Popular(위키드) - 한보라
5. I'll never love again(스타이즈본 OST) - 진태화
6. Come what may(물랑루즈) - 듀엣
```

### 기대 결과

```text
추정 가수명: 진태화 한보라

진태화 한보라 / 그게 나의 전부란 걸(번지점프를 하다) - 듀엣
진태화 한보라 / 봄날은 간다(봄날은 간다 OST) - 한보라
진태화 한보라 / City of stars(라라랜드 OST) - 진태화
진태화 한보라 / Popular(위키드) - 한보라
진태화 한보라 / I'll never love again(스타이즈본 OST) - 진태화
진태화 한보라 / Come what may(물랑루즈) - 듀엣
```

### 주의

추정 가수명이 이미 있는 셋리스트 본문에서는 `곡명 - 담당자`를 함부로 가수/곡명으로 뒤집지 않는다.

---

## 14. 중복 곡 테스트

### 입력

```text
260605 윤마치 MRCH
셋리스트

휴먼매커니즘
Color it
유일한향기
휴먼매커니즘
```

### 기대 결과

```text
첫 번째 휴먼매커니즘: 새 곡
두 번째 휴먼매커니즘: 붙여넣기 내부 중복 후보 또는 기본 OFF
```

---

## 15. 제목 변형 / 유사곡 테스트

### 기존 저장소

```text
N.Flying / 환절기
```

### 입력

```text
2026 Awesome Stage in Busan: N.Flying
2026/06/06 셋리스트

1. 환절기 (換節期)
2. Endless Summer
```

### 기대 결과

```text
N.Flying / 환절기 (換節期)
→ 이미 있음 또는 확인 필요/비슷한 곡 있음

N.Flying / Endless Summer
→ 새 곡
```

### 주의

`환절기`와 `환절기 (換節期)`는 원본 제목은 유지하되, 비교용 정규화 기준으로 유사곡/중복 계열로 잡을 수 있어야 한다.

---

## 회귀 테스트 우선순위

파서 수정 후 시간이 없을 때는 최소 아래 5개만 확인한다.

```text
1. 일반 가수 - 곡명
2. 카디 대괄호 헤더
3. can't be blue SNIPPET CONCERT
4. #숫자 + 가수 - 곡명
5. 곡명 - 출연자명
```

최소 테스트 입력:

```text
강진 - 땡벌
로제, Bruno Mars - APT.
10cm - 폰서트
```

```text
[카디 / KARDI💖🔥]

뷰민라 2026 셋리스트📃

WatchOut
Riot
Player 1
```

```text
260530 can't be blue SNIPPET CONCERT | May be blue
셋리스트💙

Intro+can't love
Commercial love
상사화
```

```text
[⚔️🍀용사님의 듀엣모험 셋리스트🧭🌊]
#1 AKMU(악뮤) - Crescendo(크레셴도)
#2 안예은 - 상사화
#3 안예은 - 능소화
```

```text
1. Proud of your boy - 차윤해
2. Come what may - 최지혜&차윤해
3. 놈의 마음속으로 - 차윤해&김성식
```
