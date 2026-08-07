-- =====================================================================
--  LÅTSNURRAN – Svensk rap blir spelbar: 404 låtar läkta ur artistkatalogen
--
--  0068 drog slutsatsen att modern svensk hiphop "aldrig sålts som köpmusik
--  hos Apple" och därför inte gick att spela. Den slutsatsen var FEL, och
--  felet var dyrt: 961 av den svenska pottens låtar stod markerade som
--  ohittbara, nästan hela genren.
--
--  Låtarna FINNS hos Apple. Det är SÖKNINGEN som inte hittar dem. Serverns
--  uppslag är `search?term=<titel> <artist>&limit=8`, och Apples sökindex
--  svarar så här (skarpa svar, 2026-08-07):
--
--    "Haparanda Einár"     → 0 träffar     (låten ligger i Einárs katalog)
--    "KINGSTON Haval"      → 0 träffar
--    "DJUPA SÅR Owen"      → 0 träffar
--    "14 Asme"             → 7 träffar, alla ASMR-kanaler ("Asme" ≈ "ASMR")
--    "More Life 23"        → 8 träffar, mest Chayce Beckham "23"
--    "Vindar på Mars Hov1" → 5 Hov1-låtar, men inte den som söktes
--
--  Tio av tio stickprov missade. Katalogen svarar däremot direkt:
--  `lookup?id=<artistId>&entity=song&limit=200` gav 143 låtar för Yasin,
--  142 för Hov1, 94 för Einár – med previewUrl på varenda en.
--
--  DÄRFÖR: preview-URL:erna nedan är hämtade ur artistkatalogen i stället
--  för ur sökningen. Titel, artist och år i potten rörs INTE – de kommer
--  från Sverigetopplistans veckoarkiv och är den vettigare källan. Att de
--  två källorna är oberoende gör årsuppgiften starkare, och de är rörande
--  överens: 390 av 404 låtar har exakt samma år hos Apple.
--
--  EN LAGAD RAD MÅSTE SKYDDAS. Bakgrundsjobbet (0068/0069) söker om varje
--  cachad rad efter 25 dagar och nollställer den som inte ger träff – och
--  sökningen kommer att missa de här låtarna igen, precis som förut. Utan
--  skydd hade hela den här migrationen ångrat sig själv i början av
--  september. Därför:
--
--    preview_source = 'catalog'   raden är verifierad mot katalogen, inte
--                                 mot sökningen. Bakgrundsjobbet söker
--                                 aldrig om den, urvalet litar på den utan
--                                 30-dagarsgräns, och poll_track_start får
--                                 inte nollställa den.
--    itunes_track_id              Apples eget spår-id, sparat för framtida
--                                 verifiering via lookup?id= – exakt, utan
--                                 sökrankningens nycker.
--
--  KVAR ATT GÖRA: 67 svenska låtar utan katalogträff står fortfarande
--  som ohittbara, och samma metod kan användas på de utländska. Ett
--  bakgrundsjobb som betar av potten ARTISTVIS i stället för låtvis vore
--  den riktiga lösningen.
--
--  Störst utslag (låtar som blir spelbara): Hov1 38, Yasin 37, Ant Wan 34,
--  Asme 28, Einár 24, 23 24, Z.E 18, Haval 17, C.Gambino 17, VC Barre 12,
--  Dizzy 12, Adaam 11, Owen 11, Sarettii 10, Adel 8 – plus Greekazo, 1.Cuz,
--  Dani M, Loam, Robin Kadir, Jireel, Gaboro, K27, Thrife, Denz, Infinite
--  Mass, De Vet Du, Norlie & KKV, Tjuvjakt, Petter, Linda Pira, Lamix,
--  Victor Leksell och ett trettiotal samarbetsnamn.
--
--  ÅRET SOM STÅR KVAR. 14 låtar har ett annat år hos Apple än i potten.
--  Potten behåller sitt, för Apples datum är där oftast en återutgivning:
--  Hov1 "Sex i taxin" är från 2017 (Apple säger 2020), Infinite Mass
--  "Area Turns Red" från 1995 (Apple säger 1997). Övriga ligger ett år isär
--  åt endera hållet – topplisteåret och utgivningsåret är helt enkelt inte
--  samma sak för en låt som släpps i december. Det påverkar bara kategorin
--  exakt årtal, och bara för de 14.
--
--  Additiv + idempotent. Kör efter 0070.
-- =====================================================================

-- --- 1. varifrån en preview-URL kommer --------------------------------
alter table public.track_pool
  add column if not exists preview_source   text,
  add column if not exists itunes_track_id  bigint;

comment on column public.track_pool.preview_source is
  'null/''search'' = hittad via sökningen, får sökas om och nollställas. ''catalog'' = hämtad ur Apples artistkatalog; sökningen hittar den inte, så den får ALDRIG sökas om.';

-- --- 2. läkningen -----------------------------------------------------
create temp table _lakning (pool_id int primary key, url text not null, track_id bigint) on commit drop;

insert into _lakning (pool_id, url, track_id) values
  (9393, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview125/v4/d7/bb/96/d7bb9695-830d-4963-1717-ba6702025900/mzaf_6473760079613298176.plus.aac.p.m4a', 1457442263),
  (7420, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview115/v4/42/32/3b/42323b8d-cb83-0968-ff37-017a7fa91008/mzaf_447810762677845976.plus.aac.p.m4a', 1489153715),
  (9388, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview115/v4/07/d2/9f/07d29fab-15e5-7d8e-2f62-a8737f3ac3ad/mzaf_4258323914447300609.plus.aac.p.m4a', 1470055697),
  (8657, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview115/v4/e0/39/df/e039df6d-f9fb-3cd0-706d-41c83c99f464/mzaf_14058294678057417265.plus.aac.p.m4a', 1585674343),
  (9991, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview126/v4/19/70/5b/19705bc1-6e9c-1466-52fe-a7f7e525ec5b/mzaf_138560159343927195.plus.aac.p.m4a', 1596367016),
  (10020, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview122/v4/bb/83/7d/bb837d5e-1869-2002-d47f-164a3af39ed5/mzaf_15342112475248276758.plus.aac.p.m4a', 1640666731),
  (9933, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview125/v4/34/c7/7f/34c77f30-c200-92a0-6955-e2ff2d4bcadc/mzaf_17228821912245524866.plus.aac.p.m4a', 1487357398),
  (6568, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview125/v4/da/59/15/da5915c0-da18-a303-a7e1-4c0604f2616a/mzaf_2910065504927040152.plus.aac.p.m4a', 1466975556),
  (6225, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview115/v4/50/6f/d8/506fd869-ad0f-11ee-94e1-730571ec65db/mzaf_6468953000078763285.plus.aac.p.m4a', 1482906932),
  (6549, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview116/v4/ac/01/ad/ac01ad50-7b07-a0d6-bc35-5940a2b07378/mzaf_5933718295578863754.plus.aac.p.m4a', 1596484805),
  (10014, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview122/v4/7a/7d/c1/7a7dc18b-4ac8-f27c-2259-45e84f1aff0e/mzaf_17961263607105913370.plus.aac.p.m4a', 1629013166),
  (10026, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview126/v4/82/7d/20/827d20d9-e5ee-4b2d-65df-b148f538a209/mzaf_10265153497290704675.plus.aac.p.m4a', 1714617682),
  (7935, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview122/v4/c5/22/26/c52226ce-308a-447a-7d7f-787509fd2fc8/mzaf_8017291098523115981.plus.aac.p.m4a', 1639895610),
  (8159, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview123/v4/f3/04/76/f3047601-7d1e-e107-9c13-57814f1c9c26/mzaf_2690930466985364192.plus.aac.p.m4a', 1662336419),
  (6941, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview122/v4/1a/2c/7a/1a2c7a84-d865-11a1-d633-78a107b176d7/mzaf_13579841561163608132.plus.aac.p.m4a', 1639895621),
  (7316, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview123/v4/27/3d/de/273dde92-ae0d-d5a4-47c5-05561700050d/mzaf_8356849923954722362.plus.aac.p.m4a', 1662335890),
  (9025, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview112/v4/60/2c/4d/602c4dc8-ea49-1b55-6300-949672a3dcd8/mzaf_6905340374945941047.plus.aac.p.m4a', 1629014326),
  (9467, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview126/v4/21/f4/f2/21f4f2df-4d74-57ac-702b-0bbf4e8c062f/mzaf_4009414925609929046.plus.aac.p.m4a', 1675938124),
  (9458, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview122/v4/fc/62/ee/fc62ee8e-8952-fe48-3c22-81176c76c704/mzaf_6389976821840959969.plus.aac.p.m4a', 1639895613),
  (8667, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview122/v4/dd/5f/7b/dd5f7bea-37dd-4327-d613-95a7830a9e5d/mzaf_3870410868528613452.plus.aac.p.m4a', 1639895776),
  (9026, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview112/v4/27/a7/4a/27a74aee-aa81-9e20-5d46-217fccb31a01/mzaf_17422234172327072127.plus.aac.p.m4a', 1625147308),
  (8674, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview112/v4/40/0b/3c/400b3c5f-2ea1-1a84-2072-43c4b2401f86/mzaf_12377889221426032.plus.aac.p.m4a', 1639895609),
  (6576, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview123/v4/48/1e/82/481e825a-8059-0e58-b894-067d98fecffa/mzaf_16083336805256424463.plus.aac.p.m4a', 1662336412),
  (10034, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview123/v4/21/32/27/21322764-0872-56c9-2c4d-5c1c919a0f95/mzaf_4021007550254234389.plus.aac.p.m4a', 1662336408),
  (6302, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview126/v4/99/77/11/997711d8-fa07-d0d4-b439-bd6ba49d1e65/mzaf_2004296776944702827.plus.aac.p.m4a', 1666597994),
  (10045, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview116/v4/fc/ea/f3/fceaf3ab-a70f-af55-35d0-09cf24fe9a91/mzaf_9226762000801901303.plus.aac.p.m4a', 1675937652),
  (8683, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview126/v4/4d/01/6d/4d016d32-3086-a536-44e5-a30c17f44cad/mzaf_11152554007108633210.plus.aac.p.m4a', 1675938119),
  (7447, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview116/v4/f1/31/ce/f131ceca-5189-ba35-910f-99572cbff897/mzaf_9983921208154033558.plus.aac.p.m4a', 1715344453),
  (8401, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview116/v4/a6/cd/e6/a6cde684-fcb9-a23a-edb2-7bf96945235a/mzaf_9645884988140579945.plus.aac.p.m4a', 1675937645),
  (9487, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview126/v4/0f/27/51/0f275199-71c3-3c92-6a2c-53d84d5e0cc1/mzaf_265926918545667368.plus.aac.p.m4a', 1675937640),
  (10075, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview211/v4/37/5f/54/375f542b-7dd0-ad5f-2042-f26677b5081b/mzaf_11139841727453203716.plus.aac.p.m4a', 1746122460),
  (7450, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview211/v4/a2/94/4e/a2944ede-5a15-410e-ed7e-e48b86fe9cc8/mzaf_16306152681515563701.plus.aac.p.m4a', 1748101147),
  (10076, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview221/v4/ed/45/d9/ed45d971-db90-88e2-9cde-0b8d9d8d6e20/mzaf_3802210069384975088.plus.aac.p.m4a', 1748100824),
  (9435, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview115/v4/98/c1/0e/98c10ea0-6dd7-e852-a6de-868d22fcaf36/mzaf_2640227889870401339.plus.aac.p.m4a', 1543168363),
  (8968, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview125/v4/82/15/ac/8215ac39-c73b-e616-6c5b-8b0c083cb9fc/mzaf_4762569605941659820.plus.aac.p.m4a', 1476382773),
  (8625, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview115/v4/b8/b9/bd/b8b9bd46-7aee-1e53-cbbf-0a4a69d466a1/mzaf_14507321057067534944.plus.aac.p.m4a', 1466743329),
  (9927, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview125/v4/dc/8b/2f/dc8b2f24-0ca6-fc31-84cc-0bcb63b3bb20/mzaf_5985933905267645124.plus.aac.p.m4a', 1484306537),
  (6814, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview116/v4/65/87/0d/65870d1b-9919-d9ad-4be6-a2825a353442/mzaf_8208339212879697379.plus.aac.p.m4a', 1605965599),
  (6361, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview125/v4/19/97/3b/19973b3c-bec8-7ebb-bff6-c2db73f19887/mzaf_12367644492080964961.plus.aac.p.m4a', 1581757553),
  (9024, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview112/v4/82/0e/15/820e15b8-d32a-9fd1-f3b6-90b5de3fdac6/mzaf_16566607067099490506.plus.aac.p.m4a', 1621684055),
  (7017, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview112/v4/b0/11/a0/b011a01b-b517-3ea6-42cd-ddd04c1118b9/mzaf_1357116954763394207.plus.aac.p.m4a', 1639449256),
  (6606, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview116/v4/df/a6/5e/dfa65e89-1b77-a069-8c0e-804c7ca1471b/mzaf_14375559355835544779.plus.aac.p.m4a', 1697154688),
  (9470, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview112/v4/61/ea/f5/61eaf586-1e3e-f8a8-117b-0b382c169708/mzaf_1915835193720147374.plus.aac.p.m4a', 1660551334),
  (9483, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview126/v4/3c/f7/c9/3cf7c943-7373-5c80-2361-2bbb6e53b7ff/mzaf_11918590688374242357.plus.aac.p.m4a', 1671058399),
  (8167, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview126/v4/56/8e/12/568e12f3-c757-dde1-0d41-5c31d7131b6b/mzaf_14965898203566877895.plus.aac.p.m4a', 1697154692),
  (8662, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview126/v4/8c/df/60/8cdf60f1-e875-85f6-0eb9-27226b5da58a/mzaf_17245645630565538752.plus.aac.p.m4a', 1606263933),
  (7931, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview221/v4/0c/99/45/0c99454e-34a0-f62f-5ed0-3d005d40f1a9/mzaf_14507731790798205936.plus.aac.p.m4a', 1606264662),
  (6821, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview221/v4/70/98/77/70987745-799f-0652-13c0-b58043162643/mzaf_1040060889964458453.plus.aac.p.m4a', 1756068026),
  (10011, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview126/v4/87/f9/6f/87f96f2b-1dd4-788b-8593-0c8705544761/mzaf_11304690222592088760.plus.aac.p.m4a', 1625025859),
  (7170, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview115/v4/66/a2/41/66a241fd-af72-9604-91d4-d112ed6c790e/mzaf_16969909561747321401.plus.aac.p.m4a', 1413141528),
  (9380, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview125/v4/53/b6/49/53b649e5-982e-9837-33af-095650f67b4d/mzaf_15570738965797577135.plus.aac.p.m4a', 1439890936),
  (9379, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview115/v4/23/7b/b3/237bb337-c84f-808b-e957-7761559e8981/mzaf_10129556356866372266.plus.aac.p.m4a', 1434607185),
  (9909, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview125/v4/dd/94/8e/dd948ee3-7b4b-a8ae-1464-f0b99ee24523/mzaf_2432459424424376716.plus.aac.p.m4a', 1458507282),
  (9392, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview125/v4/01/95/dd/0195dd37-0504-3677-f0d6-420bf3bf2bdd/mzaf_4809749773116018003.plus.aac.p.m4a', 1456590685),
  (8983, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview115/v4/cc/d6/8d/ccd68da4-233b-0308-985f-1d3066b3acca/mzaf_18280692613370876145.plus.aac.p.m4a', 1517107039),
  (9994, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview126/v4/43/64/4c/43644c84-bb1b-a174-7e80-f2fe5ebf0253/mzaf_9778447268384240707.plus.aac.p.m4a', 1603090753),
  (9074, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview221/v4/08/cd/12/08cd128f-dbfb-5cfb-43d0-eac4d962d732/mzaf_9516574422212108925.plus.aac.p.m4a', 1776225173),
  (7004, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview115/v4/4b/d2/5f/4bd25f5d-a436-cbe0-c07e-61a3e248b1d7/mzaf_13383892906456605189.plus.aac.p.m4a', 1462738439),
  (7566, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview125/v4/c8/ae/0e/c8ae0ec5-230a-ae59-363a-3d4823144c7f/mzaf_13649344300096061479.plus.aac.p.m4a', 1479610882),
  (8962, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview115/v4/b6/d9/a9/b6d9a963-9fc5-ec10-3167-a904d2b21f90/mzaf_6898654804187699588.plus.aac.p.m4a', 1462738443),
  (9009, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview115/v4/fd/c5/5a/fdc55a90-87f7-41e8-cf03-1098a948fe6f/mzaf_1401921502420950032.plus.aac.p.m4a', 1579431330),
  (9385, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview115/v4/e7/49/2c/e7492c39-8dbe-fb1d-c36a-e4ff61142844/mzaf_303167738158130851.plus.aac.p.m4a', 1442300334),
  (7173, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview125/v4/11/82/85/11828536-39a2-af7e-d69e-1ae1f3056889/mzaf_482725987068565206.plus.aac.p.m4a', 1438008590),
  (8958, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview115/v4/ce/ab/57/ceab571b-df2b-840f-3700-1de4e19bcbb6/mzaf_7893600830711032683.plus.aac.p.m4a', 1457239261),
  (7561, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview125/v4/89/23/b8/8923b885-4e13-d8f5-b2d3-73d5748dffae/mzaf_12252378160675606973.plus.aac.p.m4a', 1454466523),
  (8957, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview125/v4/38/36/be/3836be3d-c912-a7ac-4555-23ebed5fbf6b/mzaf_9695457910031889591.plus.aac.p.m4a', 1447445630),
  (9921, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview125/v4/bf/00/1e/bf001eae-e640-77b1-4046-7a5984d63a98/mzaf_6179220424754823200.plus.aac.p.m4a', 1476677554),
  (8363, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview125/v4/eb/22/c0/eb22c01c-98cd-7871-428a-94469952943b/mzaf_10046506952340766459.plus.aac.p.m4a', 1476677565),
  (8627, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview125/v4/b0/d7/96/b0d796cc-e8ee-37fd-8113-063f6395fce4/mzaf_7521490686497065070.plus.aac.p.m4a', 1476677558),
  (6545, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview115/v4/8d/11/f8/8d11f859-b72a-192e-7b42-c8f074700bf8/mzaf_7276970679174831396.plus.aac.p.m4a', 1447445624),
  (7005, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview125/v4/9d/8d/ac/9d8dacfb-037e-b58a-73cb-059fb8120789/mzaf_2057305957066716261.plus.aac.p.m4a', 1468469600),
  (7301, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview125/v4/32/4e/8a/324e8a51-e153-9429-4e27-9a25427276ca/mzaf_14431606135270020976.plus.aac.p.m4a', 1487113298),
  (8133, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview115/v4/c9/1d/57/c91d5700-37a9-94dd-0ed5-4e34674674c7/mzaf_16132699041855237221.plus.aac.p.m4a', 1507883405),
  (7571, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview115/v4/f6/6b/85/f66b859f-57cc-5342-6062-cd1c52b1e140/mzaf_556819090955135872.plus.aac.p.m4a', 1544582530),
  (9938, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview125/v4/2e/af/2b/2eaf2b76-0c87-3ec6-f314-f50260989168/mzaf_14035113484123769760.plus.aac.p.m4a', 1507884149),
  (8978, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview125/v4/4c/97/b2/4c97b2af-007a-c27f-a1d6-c9fdceb6cd0b/mzaf_14536776236486751667.plus.aac.p.m4a', 1507884667),
  (9946, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview115/v4/e7/f6/17/e7f6177b-6cd3-974f-5fc3-a60798dd5942/mzaf_13025544101896880151.plus.aac.p.m4a', 1507883705),
  (6744, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview116/v4/99/db/50/99db50e1-e1fc-adeb-bbf7-071f9c95ef8a/mzaf_2414689375288215816.plus.aac.p.m4a', 1555474304),
  (9984, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview125/v4/21/4c/1b/214c1b26-4411-ed02-98fb-2029da69e896/mzaf_2182871315023763906.plus.aac.p.m4a', 1590497940),
  (8382, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview115/v4/57/f3/e9/57f3e9a2-2160-305a-9119-b34b0b8f1a44/mzaf_12619951271372039024.plus.aac.p.m4a', 1577890055),
  (7740, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview125/v4/11/7b/2d/117b2d04-7741-8d50-ecb6-7ecb8ee4597a/mzaf_5925090669389427978.plus.aac.p.m4a', 1590497936),
  (6474, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview115/v4/8a/05/53/8a055317-8515-a606-7196-fb4af0ee27cd/mzaf_909408129734760413.plus.aac.p.m4a', 1572815950),
  (8996, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview125/v4/9c/99/93/9c99937a-17be-8c7b-7d91-d91a292dd6aa/mzaf_7678075777808676430.plus.aac.p.m4a', 1551804282),
  (8388, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview115/v4/3c/cd/89/3ccd8945-c920-c737-03f9-975659e93932/mzaf_13053181787261005834.plus.aac.p.m4a', 1590498105),
  (10022, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview122/v4/27/d6/c5/27d6c56a-e9a0-f9dc-8ce3-c6a1f9897f22/mzaf_3723799500317615889.plus.aac.p.m4a', 1643063145),
  (10024, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview112/v4/64/7a/f4/647af441-0b0b-6720-3b6a-1a436f1ba503/mzaf_15390422021036400509.plus.aac.p.m4a', 1649925363),
  (6524, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview112/v4/52/4a/42/524a4249-ae13-547d-46b0-ef307265b94f/mzaf_2123214578801852835.plus.aac.p.m4a', 1649925771),
  (6873, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview126/v4/89/13/84/89138431-5a11-00e5-de44-5a5350df695a/mzaf_17569172996559281970.plus.aac.p.m4a', 1681804365),
  (8684, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview126/v4/78/31/a5/7831a52f-5bb6-488e-c4a3-7645b44a22c8/mzaf_12639370642809950633.plus.aac.p.m4a', 1672686116),
  (6749, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview116/v4/29/16/e6/2916e62a-cd53-84e0-4193-f89b9d926f5e/mzaf_15624915345851957580.plus.aac.p.m4a', 1708198103),
  (9517, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview211/v4/e3/d1/32/e3d132e9-e5bb-6def-705b-162e94b55c27/mzaf_10300643089622250339.plus.aac.p.m4a', 1755969240),
  (10068, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview116/v4/3b/35/df/3b35dfe8-6a84-0c52-da02-47d3518a2aef/mzaf_8270896440838950600.plus.aac.p.m4a', 1729856530),
  (8176, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview211/v4/d7/7c/3d/d77c3d72-b802-7c99-8c8a-fb47e2bc828e/mzaf_645473952179922261.plus.aac.p.m4a', 1762884809),
  (9511, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview116/v4/dd/ae/09/ddae0932-6bfa-82ff-a8b4-9982048c0b0f/mzaf_10924130758720850827.plus.aac.p.m4a', 1729856250),
  (9519, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview211/v4/db/e2/84/dbe284db-593a-0374-fc0a-182723dc65e7/mzaf_15823240473253603129.plus.aac.p.m4a', 1762884614),
  (7556, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview115/v4/9c/ef/d0/9cefd05b-870e-febe-5c5a-d724e39c4a6c/mzaf_16918975653397134701.plus.aac.p.m4a', 1439318263),
  (8370, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview125/v4/9f/56/ed/9f56ed98-c94a-d4e8-048a-9d3f56c1aa84/mzaf_10443333163769350038.plus.aac.p.m4a', 1495088245),
  (7727, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview115/v4/8d/24/6f/8d246f38-9ba1-709d-8ae3-5c85fdff24f9/mzaf_2829094456989208567.plus.aac.p.m4a', 1516899998),
  (9420, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview125/v4/17/50/f9/1750f946-dc64-4c8a-f3ba-34e7d7c4da67/mzaf_638905627039637738.plus.aac.p.m4a', 1499661697),
  (8980, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview125/v4/75/af/11/75af116e-bba0-23d9-65bc-c1d3a36e7147/mzaf_7798616612978193841.plus.aac.p.m4a', 1499661702),
  (9958, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview115/v4/a4/fd/0d/a4fd0d51-08ad-48fa-4fdb-182946c2843f/mzaf_223886692135679542.plus.aac.p.m4a', 1533840250),
  (9971, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview125/v4/2c/b5/e2/2cb5e22d-337f-c7aa-5e78-29774bdc30c1/mzaf_9976886059703307916.plus.aac.p.m4a', 1567187678),
  (9442, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview125/v4/64/69/0c/64690c12-51d7-52b3-5775-a98d7400cfc7/mzaf_16007737072553132511.plus.aac.p.m4a', 1547453738),
  (6350, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview125/v4/a4/94/e4/a494e4b2-dbca-3982-2f08-539152818303/mzaf_10565706122083762014.plus.aac.p.m4a', 1567187522),
  (9004, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview125/v4/2a/68/21/2a68213c-cac9-1fc6-bc1d-fabf04f8dec6/mzaf_6259405883695421531.plus.aac.p.m4a', 1567187676),
  (7741, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview126/v4/09/3c/9f/093c9f20-c0cf-2d16-6345-5bf85a955f43/mzaf_7324325575086480136.plus.aac.p.m4a', 1593366629),
  (9002, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview125/v4/71/ee/04/71ee04b5-6cce-3953-b87d-d61fd6bdeebd/mzaf_16383694099838241705.plus.aac.p.m4a', 1567187514),
  (9456, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview122/v4/f9/16/2b/f9162b03-e97d-8b83-7aa2-297d34a3e210/mzaf_2359338179886934553.plus.aac.p.m4a', 1617853298),
  (8669, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview112/v4/ca/33/1c/ca331cfe-8eab-faa6-5c8e-758494f7b721/mzaf_13305691062776401372.plus.aac.p.m4a', 1617852947),
  (8154, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview112/v4/aa/47/9d/aa479d34-17a1-1f44-d032-74689ab13ce1/mzaf_17999324228204655622.plus.aac.p.m4a', 1617852948),
  (7310, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview112/v4/86/4f/3d/864f3de1-167c-4cbc-6596-dab9e3b3148b/mzaf_6331428763781987372.plus.aac.p.m4a', 1617852936),
  (7587, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview116/v4/9d/cc/00/9dcc00ba-571a-c5b8-dfe0-240aa0f1ab39/mzaf_811684566338319712.plus.aac.p.m4a', 1710687510),
  (9480, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview126/v4/ef/3b/95/ef3b9540-67e9-ad4e-92d6-780d36d9b69a/mzaf_5861871756137686123.plus.aac.p.m4a', 1669633326),
  (9492, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview116/v4/06/76/9e/06769e0e-2aab-75e2-b735-acebd4751526/mzaf_2666910611539822241.plus.aac.p.m4a', 1683321823),
  (8687, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview116/v4/b0/71/54/b0715429-4235-dcbd-a135-8abb6439ba2a/mzaf_5601826383126161423.plus.aac.p.m4a', 1710687513),
  (8404, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview116/v4/0c/bc/88/0cbc889d-b0b6-eea3-3a24-db92b6f7a4be/mzaf_8462836317168949281.plus.aac.p.m4a', 1707033398),
  (7099, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview126/v4/ef/bd/12/efbd125a-8f43-0cb3-5ee0-8ed5f18921f1/mzaf_4835571159654450296.plus.aac.p.m4a', 1689702170),
  (7103, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview211/v4/b5/65/6d/b5656d4b-452c-c24a-25a3-76d20ee44b29/mzaf_5725664755683930376.plus.aac.p.m4a', 1751770434),
  (6878, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview221/v4/a2/b2/5c/a2b25c0b-bfd9-07d0-837c-a7957f824f95/mzaf_12859956503217227702.plus.aac.p.m4a', 1775189477),
  (9537, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview221/v4/60/44/52/604452d9-132d-42be-e1da-9dd63b88be27/mzaf_6831733233319128825.plus.aac.p.m4a', 1816088372),
  (9525, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview211/v4/c0/76/9b/c0769b71-a044-4098-6585-3ee1362f4ee9/mzaf_10788516681032044896.plus.aac.p.m4a', 1788964527),
  (9533, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview221/v4/c4/af/f8/c4aff8be-cf6b-1636-eb99-60ff0b5a061a/mzaf_5218489517982496667.plus.aac.p.m4a', 1816088383),
  (10104, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview221/v4/b9/05/a3/b905a309-9755-5207-05ee-e276634584bc/mzaf_18114848970810127785.plus.aac.p.m4a', 1861735008),
  (9897, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview115/v4/90/39/4c/90394c7b-2300-6778-fd74-1622a0ef5f39/mzaf_1993370040810436212.plus.aac.p.m4a', 1441125234),
  (7187, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview221/v4/c4/a2/23/c4a22388-7a90-6e06-6d53-1e76e12dc0b2/mzaf_1674839503632254550.plus.aac.p.m4a', 1764297922),
  (9071, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview211/v4/53/7d/8b/537d8b7a-3d2c-52fa-56f3-23041118045d/mzaf_15221377124993312929.plus.aac.p.m4a', 1780367295),
  (8135, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview115/v4/c2/7b/64/c27b64e2-6267-9c91-50cb-edb2d1002052/mzaf_2263698385299541022.plus.aac.p.m4a', 1535177115),
  (9944, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview115/v4/9c/57/4d/9c574dae-3dc2-0fbd-8892-37c237961299/mzaf_5989532422293721278.plus.aac.p.m4a', 1502776924),
  (7576, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview221/v4/db/c1/18/dbc118f3-8e42-41fa-c8a7-11c7a69fcba4/mzaf_1984167180349759912.plus.aac.p.m4a', 1707821025),
  (9011, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview116/v4/0a/69/d7/0a69d72b-bc8a-51c6-0981-ba5eebeb940d/mzaf_7027169578624678907.plus.aac.p.m4a', 1707820752),
  (7437, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview221/v4/46/97/36/46973601-d991-8822-a140-82f053207b9d/mzaf_5888549869474052743.plus.aac.p.m4a', 1707825294),
  (7743, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview126/v4/cb/06/32/cb0632a8-75dc-24ce-86fa-3c2f45241cdf/mzaf_6393143305660988854.plus.aac.p.m4a', 1707517276),
  (9993, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview221/v4/7b/21/bf/7b21bf25-7c82-07d0-928f-60bb18f44f4e/mzaf_12721700206670536867.plus.aac.p.m4a', 1707825119),
  (9461, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview126/v4/6b/fd/54/6bfd5494-2c12-b75c-4f1c-ae5dcf71b4dc/mzaf_7323410119966089442.plus.aac.p.m4a', 1707418463),
  (10031, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview126/v4/7f/45/89/7f458984-540c-70f0-b481-25006b088075/mzaf_5983909685628907487.plus.aac.p.m4a', 1707428720),
  (6551, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview221/v4/a0/9c/15/a09c15d6-3e2f-0180-755d-0021303030f5/mzaf_1178082086648680357.plus.aac.p.m4a', 1802926289),
  (9043, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview211/v4/8d/3a/0e/8d3a0ed8-b392-d437-c2bc-b313bbc23267/mzaf_2376142955468164637.plus.aac.p.m4a', 1707371604),
  (9503, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview221/v4/44/c5/41/44c54141-b5ea-c1e2-5c54-156902ee19e5/mzaf_9636712703963602412.plus.aac.p.m4a', 1711695058),
  (6462, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview211/v4/18/4d/5f/184d5f33-e233-4207-8827-d7798e52164b/mzaf_6349295849293750083.plus.aac.p.m4a', 1737425626),
  (9478, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview116/v4/75/20/f1/7520f189-47d2-0b17-5efa-79365331d3b1/mzaf_12060393547271597821.plus.aac.p.m4a', 1707413567),
  (10072, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview221/v4/d1/c6/3a/d1c63ae1-1c7e-75b3-2fed-f483ffe0e5f5/mzaf_18042102983464380325.plus.aac.p.m4a', 1737424634),
  (6608, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview221/v4/d1/51/cc/d151ccae-68f0-5098-a114-5b27ec0fc49e/mzaf_3372727745946805790.plus.aac.p.m4a', 1747598042),
  (6751, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview211/v4/b9/b5/77/b9b57737-17ec-3286-5b51-d5fdb2ff19a0/mzaf_14471773733661597402.plus.aac.p.m4a', 1740801103),
  (7943, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview221/v4/8a/da/5a/8ada5ac5-88e4-17be-5530-9da0352db400/mzaf_359952035400889220.plus.aac.p.m4a', 1737425427),
  (10064, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview211/v4/9c/8a/d3/9c8ad3df-9997-3c4e-c016-dd191a291644/mzaf_4614931352413539777.plus.aac.p.m4a', 1720062582),
  (9061, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview122/v4/9c/a4/6c/9ca46c63-5f5b-c809-e33f-b79f1ec5323d/mzaf_16263001836380656230.plus.aac.p.m4a', 1734713768),
  (7923, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview125/v4/8b/5e/ad/8b5eada4-0a50-4883-deb8-9de1116bb98a/mzaf_18178640882432604100.plus.aac.p.m4a', 1517815959),
  (9003, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview115/v4/ea/79/93/ea7993f8-26e4-a913-0c9a-37f2507612d1/mzaf_8257118005203566407.plus.aac.p.m4a', 1563914215),
  (9451, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview126/v4/f3/88/77/f388772f-53ee-7d42-14ab-9dbb330ea75c/mzaf_6072826226804571134.plus.aac.p.m4a', 1609076145),
  (9021, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview112/v4/02/fb/9d/02fb9d1d-6c5c-a13b-7f58-721efb951e8d/mzaf_14906647610701215560.plus.aac.p.m4a', 1614464779),
  (10061, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview126/v4/da/5e/da/da5eda1c-b3a6-f551-8a48-3ad5c9ffbec4/mzaf_13529732146085598935.plus.aac.p.m4a', 1706834749),
  (6283, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview122/v4/cf/0b/50/cf0b5052-014e-48b0-4294-e67ad23f290f/mzaf_5026189827925556501.plus.aac.p.m4a', 1466774842),
  (8670, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview112/v4/c0/97/d3/c097d368-94bb-cee6-6ba6-b48ab40e25b1/mzaf_2325945462864080664.plus.aac.p.m4a', 1620545317),
  (8386, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview115/v4/15/bc/85/15bc85bc-a81b-2103-5197-708a6b7fddb1/mzaf_8842192622061262426.plus.aac.p.m4a', 1584942298),
  (7882, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview126/v4/d0/18/92/d018920f-469b-d6e9-9c04-acaa6f2a10f5/mzaf_12303252670912442942.plus.aac.p.m4a', 1717980357),
  (6925, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview126/v4/67/e6/94/67e69482-2e30-e640-9385-8289d2786ebb/mzaf_15899493925421186519.plus.aac.p.m4a', 1717638214),
  (6444, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview211/v4/ca/60/d3/ca60d3f6-68a5-353d-19d9-962b0871f076/mzaf_6779795309220178063.plus.aac.p.m4a', 1759145716),
  (10077, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview221/v4/af/23/60/af236092-a0cd-cebf-7c2f-06624e1a9c65/mzaf_857411328311057030.plus.aac.p.m4a', 1751694025),
  (9474, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview112/v4/73/ae/f2/73aef2a7-46bf-14c4-fa10-621e104b4163/mzaf_16429313340321868490.plus.aac.p.m4a', 1660074484),
  (9391, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview116/v4/62/6b/30/626b306f-21f6-07ea-8a46-7a1758a82d32/mzaf_2255636865515895488.plus.aac.p.m4a', 1694313523),
  (6869, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview211/v4/d7/3e/7e/d73e7ed1-f7ac-c623-b3a8-17c2e78238c2/mzaf_11471225272914670041.plus.aac.p.m4a', 1767450886),
  (7430, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview211/v4/c4/93/4a/c4934a60-1128-ba76-6872-bfa51ca32bbd/mzaf_9447279951055089904.plus.aac.p.m4a', 1767355378),
  (9965, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview221/v4/93/03/b6/9303b6a0-b0a1-39b4-9695-f54e920778c0/mzaf_7463129661770119132.plus.aac.p.m4a', 1767450040),
  (9029, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview211/v4/de/a8/1a/dea81a60-d1d8-f241-2d72-d98b45ede1d4/mzaf_10724658938289641363.plus.aac.p.m4a', 1767449040),
  (6574, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview221/v4/a3/af/2a/a3af2a72-89c7-29a3-36d6-7c14b220eebb/mzaf_15266450004776135519.plus.aac.p.m4a', 1767448263),
  (10063, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview116/v4/28/aa/cb/28aacb3c-a318-8d97-0238-913d5f4f1d8a/mzaf_11919494653689564335.plus.aac.p.m4a', 1727189028),
  (7097, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview221/v4/a1/cd/0f/a1cd0fae-e773-1dc2-6b2f-42e5d5b55d4f/mzaf_2520211439527850466.plus.aac.p.m4a', 1767450312),
  (6463, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview116/v4/dc/df/a6/dcdfa6d8-5788-8e74-a013-60b8731696df/mzaf_14656814640202851928.plus.aac.p.m4a', 1727188838),
  (7319, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview211/v4/2c/3d/2a/2c3d2acc-76ff-f878-3b0c-9c5f29595562/mzaf_5415815039256940053.plus.aac.p.m4a', 1767471782),
  (10035, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview211/v4/93/c7/79/93c7791f-b83e-f656-b3fb-bc73324c1784/mzaf_4988348005946048837.plus.aac.p.m4a', 1767448941),
  (10067, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview116/v4/31/9f/21/319f2103-f990-37b4-4dab-f5470880f60d/mzaf_16093424164390464770.plus.aac.p.m4a', 1727188837),
  (10084, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview211/v4/9e/0b/ab/9e0bab26-f295-49aa-1f3b-989b312dde5a/mzaf_14675651269015595673.plus.aac.p.m4a', 1795435976),
  (9434, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview125/v4/9a/65/0a/9a650ac2-f6c6-5e0e-8d23-c1ceb94f6e24/mzaf_17921927683603788179.plus.aac.p.m4a', 1528311967),
  (9916, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview115/v4/14/43/39/14433923-4665-2b79-eaa8-69e6fb127ba3/mzaf_16729488817310230145.plus.aac.p.m4a', 1466941545),
  (6739, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview115/v4/b5/8c/73/b58c73d0-1aad-67bc-0772-c8350ce31831/mzaf_7303863617587994290.plus.aac.p.m4a', 1466941541),
  (6278, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview115/v4/6b/a0/49/6ba0497c-05e5-de8e-751e-c6dd13922288/mzaf_16857545157734201128.plus.aac.p.m4a', 1466941371),
  (7419, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview125/v4/86/c2/ea/86c2ea8e-fc0e-b7de-a312-4eb8781b8383/mzaf_6712107647714442358.plus.aac.p.m4a', 1466941534),
  (3151, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview221/v4/d9/1a/9d/d91a9d81-fe20-120b-5f08-1ca50767d9d2/mzaf_15549547274620533752.plus.aac.p.m4a', 1450336711),
  (9397, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview115/v4/fe/b3/3d/feb33d66-7d0b-a68e-8925-032ada0a4679/mzaf_17156239405431372599.plus.aac.p.m4a', 1466941530),
  (6738, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview115/v4/ff/96/bf/ff96bf23-b19b-c414-b1a1-53050bdacadb/mzaf_13445780668222198237.plus.aac.p.m4a', 1466941374),
  (8990, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview115/v4/da/65/ca/da65cac2-83e1-61ff-d99f-eaaf4e1e6d88/mzaf_1888696119159954582.plus.aac.p.m4a', 1533596432),
  (7086, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview115/v4/29/fb/c5/29fbc5d6-2549-ed44-fe2d-df863781135a/mzaf_13948301238870951413.plus.aac.p.m4a', 1510953835),
  (8982, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview115/v4/ba/dc/3a/badc3ae7-b725-466a-7f53-506803cca353/mzaf_5581143454934652728.plus.aac.p.m4a', 1510953831),
  (9432, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview115/v4/c0/92/37/c0923737-e1f1-571a-cfd7-ad0d099559f4/mzaf_17259948934693776809.plus.aac.p.m4a', 1533596434),
  (9950, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview115/v4/53/42/53/5342536d-7956-2379-643b-728894bf62b4/mzaf_7355077600193627398.plus.aac.p.m4a', 1510953821),
  (9423, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview115/v4/11/f9/b0/11f9b07a-c3c6-1f7a-be3b-88625a0eff0e/mzaf_16868825313671817048.plus.aac.p.m4a', 1510953824),
  (6343, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview125/v4/ca/1f/35/ca1f35c4-37fb-fde2-c30f-5f0c8df37d16/mzaf_1143713082093803681.plus.aac.p.m4a', 1587162854),
  (8381, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview115/v4/0e/41/47/0e414738-9026-d75d-295b-93fb36fddef9/mzaf_4294228077570654875.plus.aac.p.m4a', 1572610053),
  (7731, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview125/v4/5d/76/2d/5d762d1a-10e8-4f5c-ad8a-bed8c881f7f9/mzaf_14708136006687551256.plus.aac.p.m4a', 1551718407),
  (8394, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview112/v4/40/d6/a2/40d6a23a-9853-00bf-0e14-6c1a3139b11f/mzaf_9443211671506157880.plus.aac.p.m4a', 1627678861),
  (7315, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview122/v4/89/01/d5/8901d5c4-f1db-2e9b-ef08-9cf0c748cbbb/mzaf_17289506218747247312.plus.aac.p.m4a', 1652319624),
  (8155, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview112/v4/5d/d3/72/5dd37223-f5b7-efef-c896-16fd74edbc98/mzaf_6969841293423942424.plus.aac.p.m4a', 1627679016),
  (6573, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview122/v4/f1/0a/38/f10a38d1-d999-624e-6e84-22d06035f611/mzaf_3865109752861780804.plus.aac.p.m4a', 1627678863),
  (6605, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview112/v4/11/6b/cb/116bcb07-77e5-848c-3ac3-6b259341c000/mzaf_4145562739786451780.plus.aac.p.m4a', 1627678856),
  (7317, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview123/v4/31/ea/f5/31eaf5c8-0e57-1d02-2973-43a7546cbb95/mzaf_14697611664724096213.plus.aac.p.m4a', 1665911605),
  (7185, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview221/v4/e9/f8/4b/e9f84b94-3383-99b0-5252-c97390ef4f74/mzaf_13629147272416240073.plus.aac.p.m4a', 1698294825),
  (6577, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview116/v4/3d/96/ec/3d96ecb8-e98c-a898-a356-ad0708accb6c/mzaf_3068785196183867566.plus.aac.p.m4a', 1690368949),
  (8984, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview125/v4/13/eb/37/13eb3740-30bd-c625-425d-f050a07fe241/mzaf_6569366414948753788.plus.aac.p.m4a', 1527398980),
  (7009, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview125/v4/05/c5/11/05c511c7-0f22-2f57-8d55-26ad69900cee/mzaf_11120229112023218613.plus.aac.p.m4a', 1525693727),
  (6408, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview116/v4/f4/91/5d/f4915d68-2257-e092-53d3-579a672762e5/mzaf_6555713123713244028.plus.aac.p.m4a', 1707845275),
  (7308, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview125/v4/ab/81/69/ab81699f-1a2e-b359-d951-b94898a903d9/mzaf_11953829792993196315.plus.aac.p.m4a', 1590364532),
  (8675, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview221/v4/f8/ce/cc/f8cecc2c-9ea9-21e3-d3d3-cc934167a676/mzaf_14337882584661902107.plus.aac.p.m4a', 1747857007),
  (9045, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview116/v4/13/f9/2f/13f92fda-abd1-330f-bda4-75844ed732b2/mzaf_17226765921060000536.plus.aac.p.m4a', 1693429802),
  (7939, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview116/v4/90/8f/57/908f575f-1595-cc6a-dfe5-20450fb28860/mzaf_567949320828802844.plus.aac.p.m4a', 1668793270),
  (7951, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview211/v4/10/99/96/109996a4-5752-f2a1-b231-58328e8f1f6a/mzaf_15002660498811794715.plus.aac.p.m4a', 1783334872),
  (6360, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview211/v4/d1/89/3c/d1893c5f-d7e4-80b9-1ac4-d7aab51b90a7/mzaf_16048540357958664737.plus.aac.p.m4a', 1621265085),
  (6933, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview112/v4/08/81/94/088194b5-6834-f943-304e-a1b42055ff6a/mzaf_3005702038018044329.plus.aac.p.m4a', 1621265354),
  (9945, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview112/v4/24/77/c6/2477c6eb-deeb-9be5-bbdf-361ab85982e8/mzaf_16687882606244879045.plus.aac.p.m4a', 1621266323),
  (6741, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview122/v4/b0/19/11/b0191192-ec86-5f86-ef1a-b7e3fc345e21/mzaf_13412770217189257837.plus.aac.p.m4a', 1621265495),
  (9941, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview122/v4/f6/68/d9/f668d9c7-4e67-5d52-ba89-2edb6428f8e4/mzaf_18383846917840645392.plus.aac.p.m4a', 1621264551),
  (10003, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview211/v4/ef/c7/41/efc741ac-4975-ceea-6eed-de18648bbbc2/mzaf_184490898809683328.plus.aac.p.m4a', 1781655442),
  (7723, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview126/v4/3d/a1/3c/3da13ca5-176e-b3f4-d0cc-35cb1be0f0a6/mzaf_507320228513022259.plus.aac.p.m4a', 1621264972),
  (7570, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview211/v4/e4/f2/31/e4f231ae-ce9c-b463-6a79-d34e91eafbde/mzaf_1326505200687840760.plus.aac.p.m4a', 1859802853),
  (8134, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview211/v4/c9/c8/22/c9c82243-fdeb-f82d-af6a-464ba1ee5d37/mzaf_4264611254189145259.plus.aac.p.m4a', 1860151936),
  (8136, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview221/v4/65/46/3d/65463db2-4e8c-e954-4ada-35f2a2ec3ade/mzaf_16983069691874617032.plus.aac.p.m4a', 1859802369),
  (8645, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview211/v4/f8/dd/aa/f8ddaa67-e1c6-903c-618e-91a45cfe1135/mzaf_14190074062050170119.plus.aac.p.m4a', 1861613683),
  (8142, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview221/v4/69/b7/bc/69b7bc07-eebd-6c97-8c71-cc0c9be2d48a/mzaf_18244898710834453876.plus.aac.p.m4a', 1860116644),
  (7575, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview211/v4/43/b8/a3/43b8a3b0-88f1-a787-f4bd-fef95dcce7e3/mzaf_2991884890264247919.plus.aac.p.m4a', 1860971923),
  (9446, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview211/v4/f1/b5/c1/f1b5c103-9c4c-7cd4-e0a0-9b7b17453bbc/mzaf_8922304594593853230.plus.aac.p.m4a', 1860381677),
  (8144, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview211/v4/eb/56/da/eb56da2b-1292-7191-5d5e-ae43ec20ea54/mzaf_14435549507769723356.plus.aac.p.m4a', 1859748455),
  (8153, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview211/v4/b2/70/10/b27010e9-eff6-87cb-8287-c8f4c186af8c/mzaf_6485259919474846742.plus.aac.p.m4a', 1860115406),
  (8677, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview221/v4/7a/24/d7/7a24d7cb-81e6-1194-79db-a63fadeb99a5/mzaf_3796263799074556686.plus.aac.p.m4a', 1859842596),
  (9031, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview211/v4/4e/1b/5d/4e1b5da9-cc2e-929f-9608-1c58bdd3aeb8/mzaf_15726833885111139568.plus.aac.p.m4a', 1860392778),
  (9491, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview221/v4/2a/01/43/2a0143c6-8553-3317-e1b1-1f8e0adf412c/mzaf_14126183265325253631.plus.aac.p.m4a', 1859846309),
  (7747, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview221/v4/a9/13/4a/a9134a60-1b6b-95b5-b738-394db5e7cf21/mzaf_5472631944763929151.plus.aac.p.m4a', 1859802802),
  (7184, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview221/v4/b6/52/f9/b652f9e2-7932-c659-49cb-b8524d3b3430/mzaf_13033789124602195196.plus.aac.p.m4a', 1860395511),
  (9056, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview221/v4/71/6d/02/716d02d2-65ca-bdf5-b9c1-b3940cd9f5b7/mzaf_3374347730254873652.plus.aac.p.m4a', 1860068770),
  (10079, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview211/v4/27/3a/49/273a4934-b9c3-ba86-e375-64f8464f234f/mzaf_6626401650486480280.plus.aac.p.m4a', 1860059266),
  (10083, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview211/v4/2d/d2/05/2dd2058c-eb40-6a14-d68b-b7282270b560/mzaf_11445124877836213912.plus.aac.p.m4a', 1859758073),
  (8395, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview221/v4/bd/69/38/bd6938ae-ffd0-3b43-d294-730bf55094ae/mzaf_12461626442856736067.plus.aac.p.m4a', 1860110799),
  (8099, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview115/v4/59/fc/e5/59fce551-fb36-84ee-26f7-a8481d992412/mzaf_17849083034772966758.plus.aac.p.m4a', 1442412413),
  (6420, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview115/v4/4e/6f/bf/4e6fbf67-b2bb-af1a-7991-ec90c91de0ce/mzaf_11538385629080782613.plus.aac.p.m4a', 1442412405),
  (9872, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview125/v4/e1/b3/85/e1b385df-92e9-6af0-87b7-9fe69bedd599/mzaf_13770084950732699740.plus.aac.p.m4a', 1492309720),
  (6680, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview115/v4/09/f0/d9/09f0d9f9-8dd4-a128-fec9-9bb011393f28/mzaf_14826368086147119294.plus.aac.p.m4a', 1435481110),
  (6998, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview125/v4/87/57/45/87574511-898d-1998-20ac-917b5c828c2f/mzaf_17421809301947613816.plus.aac.p.m4a', 1435481095),
  (7553, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview115/v4/3b/07/f4/3b07f452-dfad-77a2-8b6a-5b89babb5041/mzaf_1583338106330206730.plus.aac.p.m4a', 1435481099),
  (6219, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview211/v4/c8/80/6b/c8806b06-cdb2-1b80-5f22-533581771b6f/mzaf_12211286216400909838.plus.aac.p.m4a', 1606991244),
  (8111, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview115/v4/7c/1c/15/7c1c15cd-48c2-98e1-173f-d4fca29be295/mzaf_16152803032124141333.plus.aac.p.m4a', 1435481093),
  (9884, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview125/v4/3e/ed/82/3eed827b-a1bc-e0dd-6a85-9e29b41abf4c/mzaf_12100908109354770993.plus.aac.p.m4a', 1435481108),
  (9883, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview115/v4/a3/49/e6/a349e689-998b-fff2-edb6-cb9998cbf052/mzaf_17829415162941594322.plus.aac.p.m4a', 1435481097),
  (9912, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview125/v4/ba/64/03/ba640338-bace-9ce7-1acd-d158058fe393/mzaf_5325695463281596663.plus.aac.p.m4a', 1463167439),
  (7002, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview125/v4/a9/6d/8c/a96d8cff-62a8-9f03-bc82-65b1d3532b5e/mzaf_8631363223145986355.plus.aac.p.m4a', 1463167437),
  (9910, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview125/v4/91/ca/bd/91cabd28-a6b4-3442-c962-48999d54aa81/mzaf_5997249872947222173.plus.aac.p.m4a', 1463167436),
  (6598, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview115/v4/62/ac/c7/62acc759-4c40-e762-4bd2-4c9d0c2c6e0a/mzaf_1493057814520895426.plus.aac.p.m4a', 1463167440),
  (9415, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview115/v4/d5/47/e9/d547e998-bab2-a59c-ce1b-0148c04d1ea1/mzaf_15696412558239185180.plus.aac.p.m4a', 1492309717),
  (9980, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview115/v4/e7/71/ce/e771ceee-070c-e2cb-7540-959dbf3decbd/mzaf_16989631143064190040.plus.aac.p.m4a', 1586625822),
  (9981, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview125/v4/6e/43/b4/6e43b4be-d351-7684-80e7-a59adecb5871/mzaf_10755680198709737458.plus.aac.p.m4a', 1586625825),
  (6311, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview211/v4/b6/ae/53/b6ae53dc-b784-f9cd-c671-bbde07b6f880/mzaf_1975199234548640178.plus.aac.p.m4a', 1678575849),
  (7738, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview221/v4/57/56/11/57561157-5f42-fadb-08bc-a587cec845b8/mzaf_3622099805354034904.plus.aac.p.m4a', 1590938756),
  (8148, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview116/v4/03/df/0d/03df0d28-b48d-0588-dd98-7ea7e8b95f14/mzaf_10029475979721017602.plus.aac.p.m4a', 1605738244),
  (7745, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview122/v4/d3/a7/a2/d3a7a24c-7b52-a17e-6862-631d0250e5a0/mzaf_13025578282723689605.plus.aac.p.m4a', 1640777816),
  (8676, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview211/v4/69/ab/ba/69abbafe-9a85-4d1a-5e3b-9f5d7cceb02c/mzaf_3019573034273276437.plus.aac.p.m4a', 1689438836),
  (6373, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview221/v4/4e/79/e4/4e79e4e2-3f63-89fa-7bbb-b35421a3810d/mzaf_13390755782397946525.plus.aac.p.m4a', 1775693648),
  (7941, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview126/v4/be/02/27/be0227d1-4e5d-6148-847a-1f9407540ba9/mzaf_10205036075281943136.plus.aac.p.m4a', 1705417229),
  (8168, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview116/v4/67/bf/49/67bf492c-b51c-5bfc-4f45-02fbbde4691d/mzaf_12183264825624088782.plus.aac.p.m4a', 1701386796),
  (9514, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview211/v4/e3/c9/55/e3c955c1-7127-7c6f-fac4-cdee31190d3b/mzaf_5996897782262617881.plus.aac.p.m4a', 1744912406),
  (6279, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview211/v4/2f/11/9d/2f119db4-4b64-7655-4896-afbc447f6f95/mzaf_17548624703204853896.plus.aac.p.m4a', 1775693745),
  (10073, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview211/v4/0e/0e/5f/0e0e5f6d-6e50-e4a1-145a-1d73a26ade05/mzaf_2253946907745553398.plus.aac.p.m4a', 1775693644),
  (7102, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview211/v4/f8/1f/f4/f81ff4d7-f283-442c-a189-5e4d5e8f997f/mzaf_7340100042020526058.plus.aac.p.m4a', 1744912400),
  (7101, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview221/v4/84/28/66/8428664c-b0bf-7f9a-baf0-51e7205f3316/mzaf_2123521115443174339.plus.aac.p.m4a', 1744912407),
  (10078, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview221/v4/a9/1b/b0/a91bb0cd-59d3-5039-3d41-15a54d535f80/mzaf_1678996672679434531.plus.aac.p.m4a', 1764919220),
  (9068, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview221/v4/5e/c4/f3/5ec4f3f2-87fc-a9d1-8d19-4614afb7e5a9/mzaf_3066899940921500021.plus.aac.p.m4a', 1775693741),
  (8411, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview211/v4/d5/00/49/d500493e-ce03-7cb6-12eb-db2150753612/mzaf_6968289786207347300.plus.aac.p.m4a', 1836107612),
  (8412, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview221/v4/86/83/7b/86837bec-971f-74d0-45d1-dc8c3cfe2ac6/mzaf_366814665438462629.plus.aac.p.m4a', 1836107602),
  (10094, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview211/v4/82/36/d6/8236d659-9627-b8bb-ae88-3c10d68d1262/mzaf_12640395887380710590.plus.aac.p.m4a', 1836107604),
  (10093, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview221/v4/cd/45/86/cd458603-2aa1-96bd-d2dd-d1cf69fa6fd7/mzaf_1619912235309726729.plus.aac.p.m4a', 1836107606),
  (6409, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview221/v4/dc/0c/0a/dc0c0a4f-72cd-4c7e-fb4a-3b37d41217ea/mzaf_9638806982531513310.plus.aac.p.m4a', 1804315908),
  (9536, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview221/v4/12/b9/e4/12b9e426-f634-e626-2550-9214dd8dd0d2/mzaf_3498239550376194318.plus.aac.p.m4a', 1815453061),
  (6596, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview115/v4/f3/57/c7/f357c7c1-9087-d024-8218-951e039ac0aa/mzaf_8825566422451293860.plus.aac.p.m4a', 1442412419),
  (6223, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview211/v4/06/d7/38/06d738be-9ac0-4aa9-9eab-fb258cf427dc/mzaf_9507326313007759462.plus.aac.p.m4a', 1680249662),
  (8387, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview115/v4/17/13/aa/1713aae5-1a92-efe7-f79c-e8408889beb5/mzaf_5525328830311661529.plus.aac.p.m4a', 1586625828),
  (10095, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview211/v4/ec/ab/4c/ecab4c8e-1d8e-3393-7aa2-e81057b24270/mzaf_10382062792632467873.plus.aac.p.m4a', 1836107607),
  (6528, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview125/v4/57/47/43/574743bd-b284-111a-4c2f-628f1cb760b0/mzaf_14745768950728234635.plus.aac.p.m4a', 351775621),
  (7787, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview115/v4/3b/a6/2a/3ba62a7c-d2ff-4a50-1506-8e02ff88db9b/mzaf_17886161900469379664.plus.aac.p.m4a', 351775515),
  (7791, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview115/v4/08/25/c8/0825c8dd-da74-881c-d6c8-c2fb3d81e755/mzaf_9720571413097364827.plus.aac.p.m4a', 351774113),
  (6963, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview125/v4/44/91/f0/4491f094-bde6-7c88-c956-477f16accbf8/mzaf_5207747151054335833.plus.aac.p.m4a', 1442543544),
  (9964, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview125/v4/7d/bf/b5/7dbfb593-dff0-1fe6-7611-b2385115930c/mzaf_566513614448642561.plus.aac.p.m4a', 1544998791),
  (9494, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview116/v4/b4/35/24/b4352465-8f6a-b725-6495-5a7417c9e1bb/mzaf_4305493845723431617.plus.aac.p.m4a', 1686196297),
  (9924, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview211/v4/b6/1a/e3/b61ae30f-7d28-db8f-8de8-e61a08332ac5/mzaf_16624441796255620425.plus.aac.p.m4a', 1478439569),
  (9903, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview115/v4/50/e6/dc/50e6dc00-063d-6713-bafe-d4ec85e39f82/mzaf_15102654063634316334.plus.aac.p.m4a', 1451320662),
  (9406, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview125/v4/83/6d/4d/836d4da1-6728-c162-9520-5808b3e7bcb9/mzaf_17428521061765588733.plus.aac.p.m4a', 1483062208),
  (9395, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview125/v4/d5/b5/7c/d5b57cbe-382d-b1df-436c-1c99f85b87d6/mzaf_4910706535607024326.plus.aac.p.m4a', 1485423562),
  (9405, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview125/v4/f8/5c/10/f85c102d-8c07-521a-037a-533e1380e7a0/mzaf_11221364575846849642.plus.aac.p.m4a', 1485274807),
  (6247, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview125/v4/2d/07/56/2d0756fc-0d79-6fa7-e13d-2b47f050a85e/mzaf_1522087110926603419.plus.aac.p.m4a', 1590360218),
  (7094, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview122/v4/3b/9c/21/3b9c21b7-0b4b-fe45-83b3-7c1bd9736b60/mzaf_729108196740040873.plus.aac.p.m4a', 1650515176),
  (6748, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview122/v4/f7/75/6c/f7756c82-83db-e079-cbd3-f0c795fb2b4f/mzaf_282726103554310013.plus.aac.p.m4a', 1644847876),
  (6372, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview116/v4/78/c4/f0/78c4f064-2333-ff2a-a1d2-6dd8b0ca8866/mzaf_17562620085096190157.plus.aac.p.m4a', 1614226837),
  (6746, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview116/v4/86/92/7a/86927a12-81ab-12e8-7787-4e20124836b1/mzaf_18237470768553421557.plus.aac.p.m4a', 1598876673),
  (6376, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview115/v4/e4/6c/ff/e46cff67-6904-eedd-7809-06bc7a3488cc/mzaf_2439330365908676052.plus.aac.p.m4a', 1444300772),
  (6265, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview115/v4/ef/72/cf/ef72cf70-0440-4161-1805-2f99f12e71e7/mzaf_16989869814718289752.plus.aac.p.m4a', 1442796058),
  (8619, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview125/v4/bd/26/97/bd269751-f763-c968-5c12-a2e37c26c287/mzaf_18252539134526725369.plus.aac.p.m4a', 1436713141),
  (9908, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview115/v4/cb/3c/fd/cb3cfd1e-47a7-8c7c-e8b0-45157357ff37/mzaf_14775442655786623877.plus.aac.p.m4a', 1458082862),
  (7010, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview126/v4/32/6d/05/326d0595-4f75-cadc-1ead-339dfbccd9f4/mzaf_17002799884635326554.plus.aac.p.m4a', 1612426321),
  (7729, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview115/v4/4b/1d/62/4b1d62b9-2beb-5ef6-4074-6a16c69be843/mzaf_8796685663537843686.plus.aac.p.m4a', 1526463402),
  (9947, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview125/v4/c9/56/3c/c9563cfd-49f4-3988-2949-2d3c88c4ee51/mzaf_3718147980843675367.plus.aac.p.m4a', 1506162975),
  (6602, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview125/v4/b0/ff/12/b0ff1266-1773-6945-8eb3-d27f8a67c0b2/mzaf_14385708513738185409.plus.aac.p.m4a', 1556678990),
  (8141, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview125/v4/71/25/ee/7125eed6-bcfa-abca-c17e-3f5f9371454a/mzaf_8124543999047613019.plus.aac.p.m4a', 1571444843),
  (8656, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview125/v4/72/a2/75/72a275e5-f301-6190-324e-9084fca30c1a/mzaf_9503644982353219850.plus.aac.p.m4a', 1583811627),
  (9455, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview116/v4/f4/f3/b3/f4f3b3ac-ef86-c572-4d37-39aae5841840/mzaf_13622683100376888449.plus.aac.p.m4a', 1611519457),
  (6688, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview122/v4/ef/54/d8/ef54d8db-9160-2113-f155-00c59c83022d/mzaf_15439507286799462344.plus.aac.p.m4a', 1636591113),
  (10006, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview112/v4/ed/9a/22/ed9a2284-b338-6ce9-1388-2832c0a0cb54/mzaf_16426061264347168232.plus.aac.p.m4a', 1621029872),
  (9453, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview126/v4/bf/61/ac/bf61ac59-c331-e25b-53a4-e7816fb5015e/mzaf_11383210373192023662.plus.aac.p.m4a', 1611519463),
  (9488, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview116/v4/52/cb/1a/52cb1a6e-cc42-cf33-ee2e-7fc4d933f77c/mzaf_487573384724408834.plus.aac.p.m4a', 1677112547),
  (7324, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview116/v4/e1/be/35/e1be358f-3086-1709-c4e3-863253e93c3a/mzaf_751972922531537072.plus.aac.p.m4a', 1725205820),
  (8181, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview221/v4/f8/4c/1b/f84c1bbd-0917-1211-f5c4-3d0827b489c7/mzaf_12359180206712761829.plus.aac.p.m4a', 1801968976),
  (7583, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview221/v4/5a/ce/42/5ace42c2-6346-9ff4-b3c7-0130dfe4396f/mzaf_3372969340887249040.plus.aac.p.m4a', 1831574323),
  (8654, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview116/v4/b3/88/a2/b388a2bc-4ab9-7238-6b48-986e1a6f9171/mzaf_12175953367358405988.plus.aac.p.m4a', 1718302050),
  (7744, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview126/v4/ca/01/fc/ca01fcba-f75f-0a41-8f5a-be369a540eb3/mzaf_1884400584123079124.plus.aac.p.m4a', 1616915441),
  (8402, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview126/v4/8a/13/2f/8a132fa0-5537-e9a1-1208-3fe87365e91f/mzaf_17390845129801088277.plus.aac.p.m4a', 1718301836),
  (9496, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview126/v4/ee/84/8a/ee848acc-1d03-814e-39a9-6629c22d66c4/mzaf_4880623953923712516.plus.aac.p.m4a', 1689209619),
  (10080, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview221/v4/52/ef/7e/52ef7eaf-8625-1401-9539-dd17d3ef5814/mzaf_17247731965545604843.plus.aac.p.m4a', 1752685254),
  (9543, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview211/v4/b4/3b/b0/b43bb0dc-44c7-4991-bdc5-282d53e557ee/mzaf_17017140249514544533.plus.aac.p.m4a', 1838720862),
  (7736, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview125/v4/f1/96/61/f1966137-9ccc-04db-8448-7bb5569636f1/mzaf_16482966329881470385.plus.aac.p.m4a', 1574290359),
  (6351, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview125/v4/26/16/dd/2616dd91-7a1b-6889-ce9f-680579b43c8b/mzaf_13123235871030902358.plus.aac.p.m4a', 1586585352),
  (6523, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview122/v4/38/d2/e5/38d2e5dd-1a39-c010-b031-d03fd21d3863/mzaf_7682457280188810938.plus.aac.p.m4a', 1620625625),
  (8685, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview116/v4/2c/b2/29/2cb229ad-505c-7626-1fe3-3b3f13c60c1a/mzaf_10121654765331048985.plus.aac.p.m4a', 1683131723),
  (7751, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview116/v4/92/40/52/9240525c-6015-be70-e1fb-00bc12fa47aa/mzaf_573758038418911585.plus.aac.p.m4a', 1716865538),
  (8165, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview116/v4/21/2e/96/212e962a-8d47-67aa-70ae-e71ca8e24255/mzaf_7719483438290528823.plus.aac.p.m4a', 1683132147),
  (6645, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview221/v4/52/50/a7/5250a7f8-cf9f-f92c-9eaa-3be37583d51f/mzaf_15101648250759209127.plus.aac.p.m4a', 1739066961),
  (6876, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview221/v4/57/ac/f5/57acf557-b45c-2aa0-ef8c-44b5611fb50b/mzaf_1371851770666453815.plus.aac.p.m4a', 1763764250),
  (10091, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview211/v4/ca/67/12/ca6712ea-f91a-2486-8924-b276962a18d8/mzaf_10083721857484760534.plus.aac.p.m4a', 1813823460),
  (9540, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview211/v4/c1/5f/6b/c15f6bc8-fcc8-b793-ca86-96851821f5a1/mzaf_4074886636034600818.plus.aac.p.m4a', 1824527756),
  (7719, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview115/v4/90/38/9d/90389dfc-7f16-0140-45ee-551f3ada3a4f/mzaf_10590839517259851603.plus.aac.p.m4a', 1468965756),
  (9416, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview115/v4/48/c3/1b/48c31b94-fa53-477a-ce7b-cc3771f841da/mzaf_11387025508293088813.plus.aac.p.m4a', 1493969310),
  (9410, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview115/v4/05/cf/5c/05cf5cd8-f1d9-3a89-ee32-8e64d08b0f80/mzaf_14045683742176756468.plus.aac.p.m4a', 1485756199),
  (7746, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview122/v4/d8/21/14/d8211400-d6af-34e5-fc57-8a31fd17805c/mzaf_13987509845218288632.plus.aac.p.m4a', 1638375678),
  (6421, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview211/v4/e2/12/a5/e212a595-78a0-c780-47ed-8f0e84f04880/mzaf_15310126046210419956.plus.aac.p.m4a', 1678576239),
  (7714, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview115/v4/2c/f3/a3/2cf3a358-5b24-1eb6-795a-d450a2a14258/mzaf_12474905566205373055.plus.aac.p.m4a', 1500747267),
  (6870, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview125/v4/65/27/40/652740f5-e8a4-4b27-42c5-6aca2bacfc64/mzaf_16731644723097078919.plus.aac.p.m4a', 1537031384),
  (9489, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview126/v4/d1/4d/1e/d14d1e6c-ae74-14ff-7e56-003a2a653b73/mzaf_2897588302940532130.plus.aac.p.m4a', 1677667865),
  (10017, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview221/v4/13/27/80/1327801d-2d51-929a-8acc-d0759653ccd5/mzaf_15651106607905550016.plus.aac.p.m4a', 1805845696),
  (7309, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview211/v4/2f/6e/4c/2f6e4c73-40d2-9b00-6ec1-14084e97d145/mzaf_3524075302321880229.plus.aac.p.m4a', 1805845382),
  (7436, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview211/v4/11/54/e0/1154e0c1-77d3-6c40-f588-473ce9dd9052/mzaf_429212327650475310.plus.aac.p.m4a', 1805845670),
  (9974, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview115/v4/a8/61/9e/a8619edc-8ac1-65e3-32b3-dab67621b9f0/mzaf_9095469169185335296.plus.aac.p.m4a', 1548299271),
  (6423, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview211/v4/02/ff/4d/02ff4df9-168a-4d39-b929-9bb9cf7e0833/mzaf_8728731769081824670.plus.aac.p.m4a', 1805844559),
  (9460, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview221/v4/66/4f/b1/664fb119-ce7c-a409-bca9-42fa59cf6cad/mzaf_1633494901320030259.plus.aac.p.m4a', 1805841726),
  (9463, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview211/v4/7f/86/24/7f862440-be1c-47e9-188d-e784f1b54ef6/mzaf_4554319242565940599.plus.aac.p.m4a', 1805846216),
  (10005, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview221/v4/20/ee/8d/20ee8d02-9332-42ce-43e7-df296d3b8916/mzaf_7408486852289560778.plus.aac.p.m4a', 1805845218),
  (8664, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview221/v4/d4/46/a6/d446a6e0-9126-9c2b-f881-be31fd5c40da/mzaf_9811301885392204407.plus.aac.p.m4a', 1805845344),
  (9481, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview126/v4/cb/22/ed/cb22edbe-a164-a334-8e82-dd4df63923d9/mzaf_8784806372909709305.plus.aac.p.m4a', 1670393087),
  (9509, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview122/v4/6e/03/9e/6e039e8e-fd3b-c2ed-aa17-81ccb41310d4/mzaf_847453366263745485.plus.aac.p.m4a', 1731813491),
  (9520, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview211/v4/a6/f5/7a/a6f57aaa-4e2e-63f5-858c-efb114088c35/mzaf_14280600383758617484.plus.aac.p.m4a', 1763821656),
  (9510, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview221/v4/98/be/2e/98be2e5d-c175-0827-d8ba-213daa42b3b7/mzaf_6417019497096427141.plus.aac.p.m4a', 1720027987),
  (7438, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview116/v4/57/c6/81/57c68163-47a3-d81a-5729-c21347f499f8/mzaf_14513107540029717144.plus.aac.p.m4a', 1715040032),
  (6248, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview221/v4/2d/91/9f/2d919fdb-276d-d24b-eb8b-6a8cfc38248a/mzaf_2437592437673256067.plus.aac.p.m4a', 1630782093),
  (6345, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview211/v4/dc/ba/6e/dcba6e23-0404-1059-7d8d-17874b3110d6/mzaf_12098429397068007711.plus.aac.p.m4a', 1744578483),
  (9374, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview125/v4/1c/56/bd/1c56bd99-ad5f-1931-62d5-62f017835f8e/mzaf_16296362759279340566.plus.aac.p.m4a', 1476680280),
  (8955, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview125/v4/e6/37/2e/e6372e9c-fb62-a2cb-3d3d-b5f2f4e66eba/mzaf_786600901109838867.plus.aac.p.m4a', 1436503755),
  (7421, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview115/v4/ea/fb/bf/eafbbf11-ce2c-4bab-266c-d2487d7e97f1/mzaf_9553786575648135450.plus.aac.p.m4a', 1492637207),
  (7568, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview115/v4/1a/15/95/1a159508-0c76-a682-73c2-6dec68ac2912/mzaf_4869314008520492570.plus.aac.p.m4a', 1492637202),
  (6640, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview221/v4/70/bd/17/70bd1700-d02d-0aef-cb97-59266c269b83/mzaf_15566981720210606745.plus.aac.p.m4a', 1819100946),
  (9951, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview125/v4/bb/99/5e/bb995eb2-9da6-2629-f63b-31852150ba03/mzaf_14748670537934662286.plus.aac.p.m4a', 1514233167),
  (8634, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview125/v4/53/f6/20/53f620d8-9367-c5a6-16da-2cd7b7a0db31/mzaf_11970160234514366739.plus.aac.p.m4a', 1514233170),
  (8991, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview115/v4/87/78/45/8778458b-f867-7c8d-f33d-361fca8f5b4a/mzaf_10062929640054846303.plus.aac.p.m4a', 1534341442),
  (8635, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview115/v4/42/aa/b3/42aab3bf-68d1-b6bd-a641-83d8e649e2d8/mzaf_3056963468808783937.plus.aac.p.m4a', 1514233172),
  (9433, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview125/v4/75/52/f4/7552f45b-03fb-0b0b-f359-b60d2ac447c3/mzaf_9201062246290187121.plus.aac.p.m4a', 1534341450),
  (6255, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview125/v4/4b/e1/9e/4be19e4b-d3e1-ee47-9e1d-58032e287687/mzaf_476684035467139251.plus.aac.p.m4a', 1514233171),
  (6497, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview125/v4/4c/78/09/4c7809bc-7577-7fdb-3c35-db53e9c3ab05/mzaf_8167940366243848498.plus.aac.p.m4a', 1492637199),
  (8992, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview125/v4/c0/0a/75/c00a756b-8bab-f303-7d5a-43452410beba/mzaf_16567219759586491860.plus.aac.p.m4a', 1534341440),
  (8973, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview125/v4/1e/0b/22/1e0b2229-20b8-f272-f0c0-ddfafe859883/mzaf_16080950544296633679.plus.aac.p.m4a', 1492637200),
  (7730, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview115/v4/3b/8c/0d/3b8c0d8d-cea8-3351-3432-73d9ba3dbdec/mzaf_7306594693730087753.plus.aac.p.m4a', 1542662297),
  (9952, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview125/v4/08/48/d9/0848d9ac-09dc-8a92-6f62-e725a4ecdecc/mzaf_15502479352813875960.plus.aac.p.m4a', 1514233166),
  (7008, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview125/v4/af/bf/da/afbfdab8-9725-b02e-273f-c0fa42c55f0d/mzaf_16498548123329853761.plus.aac.p.m4a', 1514233163),
  (6232, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview115/v4/36/63/0d/36630dda-beb5-a30b-3dd5-058c7ca967b0/mzaf_9208050189503892466.plus.aac.p.m4a', 1514233169),
  (8646, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview112/v4/24/04/d1/2404d19f-e4fb-99ca-d038-1956e7755f87/mzaf_17084791107707642442.plus.aac.p.m4a', 1652350245),
  (8995, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview112/v4/b2/ad/54/b2ad5476-3ac8-7dc4-3b11-00eef660d6bd/mzaf_11375353903619615010.plus.aac.p.m4a', 1652350350),
  (10008, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview122/v4/80/8b/6a/808b6a46-19af-3445-ae39-fd3a9b82794e/mzaf_14940396113386850647.plus.aac.p.m4a', 1623997117),
  (9016, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview126/v4/28/e2/ba/28e2bac5-6ff6-4b86-66e4-1b6ad45addc3/mzaf_8614798887191567090.plus.aac.p.m4a', 1608990187),
  (10009, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview122/v4/b8/b1/f3/b8b1f354-c648-1be8-38e0-0b5bc5c725aa/mzaf_17190794414931943407.plus.aac.p.m4a', 1624892210),
  (6461, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview126/v4/32/bd/c0/32bdc027-e3ba-ffbe-5e9d-1af99514c657/mzaf_14486575562613231085.plus.aac.p.m4a', 1674892814),
  (10004, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview122/v4/c8/8c/c5/c88cc5b5-2684-a5a2-dd26-da8c77cb8232/mzaf_17676034428028827231.plus.aac.p.m4a', 1615915550),
  (8668, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview122/v4/8e/d2/30/8ed23076-66e5-086f-fe7f-afc6fd49f8ca/mzaf_4784572098132626080.plus.aac.p.m4a', 1615915553),
  (10056, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview126/v4/78/58/c5/7858c5cf-16dc-3dd9-8d67-c6f65bb61531/mzaf_3531133364672022272.plus.aac.p.m4a', 1695937473),
  (7748, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview116/v4/6c/f1/9f/6cf19f4b-fc01-6daf-5665-0e7a55bfb438/mzaf_6858678478210832653.plus.aac.p.m4a', 1689588832),
  (6235, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview126/v4/16/0a/99/160a9904-aa89-ffbc-f0a8-e3ed71ce55c9/mzaf_1791411658063177174.plus.aac.p.m4a', 1674893351),
  (7096, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview116/v4/66/77/02/667702e2-2f3c-0118-6d31-ae63afdf01fc/mzaf_13617824441101579657.plus.aac.p.m4a', 1670127100),
  (9471, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview116/v4/a8/d9/22/a8d92227-2d7e-b4f2-a97c-e103b97df564/mzaf_17468941884347292477.plus.aac.p.m4a', 1674893030),
  (9485, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview116/v4/44/96/3c/44963cf0-1b6f-da7d-ad05-aaded3d09b96/mzaf_9524096623508430051.plus.aac.p.m4a', 1674893343),
  (9505, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview126/v4/c0/d6/9d/c0d69da1-3bfa-e501-d648-301c41e9922c/mzaf_12043047372153908030.plus.aac.p.m4a', 1716777259),
  (6610, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview211/v4/b4/4b/2e/b44b2ea7-96b3-36cf-9540-8aa517f1055b/mzaf_8495171672737177244.plus.aac.p.m4a', 1772906554),
  (7451, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview112/v4/00/f6/03/00f603d3-24e4-7fe8-20cc-c281015f5776/mzaf_18217814371560932410.plus.aac.p.m4a', 1733502382),
  (7758, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview211/v4/62/3d/fd/623dfd3b-da7a-a8c5-ff35-61c5596ae7c8/mzaf_639338711950338977.plus.aac.p.m4a', 1788568990),
  (9523, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview221/v4/43/5e/21/435e212a-baaa-fe37-88c9-40fe0dfeb630/mzaf_6069535516755048923.plus.aac.p.m4a', 1788568987),
  (9963, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview115/v4/29/0e/3d/290e3d71-e978-856d-1872-5a9a6800e93a/mzaf_14218077350663750093.plus.aac.p.m4a', 1539124187),
  (7293, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview125/v4/b6/0e/f2/b60ef22d-8b2a-dab2-15b4-c8cfa8ae6b78/mzaf_7104699716377091748.plus.aac.p.m4a', 1352748579),
  (9899, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview115/v4/c1/b2/e4/c1b2e4a9-b759-98eb-b643-981bc831a7b0/mzaf_9857426635388531886.plus.aac.p.m4a', 1443343757),
  (8616, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview125/v4/6b/f6/26/6bf62629-a673-eab5-064e-72d92ad05351/mzaf_17342926468712501750.plus.aac.p.m4a', 1380654679),
  (6384, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview115/v4/bb/5f/9e/bb5f9e0c-e9ca-00b6-789e-c87e11e64320/mzaf_4084754275022669778.plus.aac.p.m4a', 1407187619),
  (6544, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview115/v4/75/a0/a0/75a0a016-131c-8e7c-cf78-926792f82582/mzaf_9827420431519406776.plus.aac.p.m4a', 1443343762),
  (9900, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview115/v4/0d/b1/d9/0db1d9e6-d2a5-85e1-0c14-362cfbf614bc/mzaf_3015865204353108336.plus.aac.p.m4a', 1443343761),
  (6359, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview125/v4/e9/65/20/e965209b-17cb-a6c8-485a-28bd970ec532/mzaf_9720909282706948762.plus.aac.p.m4a', 1473913844),
  (9934, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview125/v4/d4/33/f4/d433f45e-01f8-32cc-7fe3-7dbf94b26e90/mzaf_17090857549554404733.plus.aac.p.m4a', 1489487195),
  (8628, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview115/v4/0e/fa/08/0efa085a-6640-24c2-6ea0-2879e2634b99/mzaf_1347336575149493202.plus.aac.p.m4a', 1479657639),
  (8361, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview125/v4/8b/91/0c/8b910c61-a16e-366d-4287-dfc6380b0de0/mzaf_7258325231422968389.plus.aac.p.m4a', 1462188065),
  (8366, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview115/v4/6e/63/15/6e631596-e43a-d659-f83c-0f5f8b079fb6/mzaf_126450479762093603.plus.aac.p.m4a', 1482678248),
  (8360, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview125/v4/d8/5e/cb/d85ecbde-0f1c-b15d-93bc-2b7c517c1a24/mzaf_13654384657147014984.plus.aac.p.m4a', 1459240174),
  (9919, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview125/v4/15/cb/96/15cb9600-64b1-cc33-6107-08d2689079e7/mzaf_5622499187390293897.plus.aac.p.m4a', 1473913838),
  (7298, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview115/v4/b3/b9/4e/b3b94e0d-e5da-1eff-8b49-39779814efdd/mzaf_5870464393869461573.plus.aac.p.m4a', 1473913841),
  (7000, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview125/v4/92/ce/fa/92cefa28-017d-0c4b-5784-63c66c6f86f9/mzaf_5274393159159437019.plus.aac.p.m4a', 1452495888),
  (8372, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview125/v4/c4/ea/af/c4eaafa2-90b8-2958-f78e-fe02fe4657ee/mzaf_2513865811648375956.plus.aac.p.m4a', 1499403624),
  (7422, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview115/v4/e6/e5/96/e6e59679-37cb-e3ef-ef61-b975ff29e6fa/mzaf_17528541558242727893.plus.aac.p.m4a', 1493027248),
  (10018, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview122/v4/46/65/94/466594cf-c734-c4cd-6315-8849d9305414/mzaf_15938821350255438926.plus.aac.p.m4a', 1637617765),
  (8960, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview116/v4/2f/a7/b1/2fa7b1ae-8ce3-f2ea-4501-82b132f1d1dd/mzaf_5657315716292484177.plus.aac.p.m4a', 1694313362),
  (7083, 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview125/v4/73/ca/b0/73cab033-9cb6-7e40-e962-17eb68e7f1cc/mzaf_11428433466958636749.plus.aac.p.m4a', 1476205686);

update public.track_pool tp
   set preview_url        = l.url,
       itunes_track_id    = l.track_id,
       preview_source     = 'catalog',
       preview_checked_at = now()
  from _lakning l
 where tp.id = l.pool_id;

-- --- 3. urvalet litar på katalograder utan tidsgräns -------------------
CREATE OR REPLACE FUNCTION public.start_random_track(p_room_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid   uuid := auth.uid();
  v_room  public.rooms;
  v_round public.rounds;
  v_track public.track_pool;
  v_req   bigint;
begin
  perform public._rate_limit('track_start', 20, interval '1 minute');
  select * into v_room from public.rooms where id = p_room_id;
  if v_room.id is null then raise exception 'Rummet finns inte'; end if;
  if v_room.host_user_id <> v_uid then raise exception 'Bara värden kan starta låten'; end if;

  select * into v_round from public.rounds
    where room_id = p_room_id order by round_number desc limit 1;
  if v_round.id is null then raise exception 'Snurra först – ingen runda att spela'; end if;
  if v_round.current_track_id is not null then raise exception 'Rundan har redan en låt'; end if;

  delete from public.pending_tracks where room_id = p_room_id;

  -- Steg 1: ospelad i rummet OCH inte känd som ohittbar.
  select tp.* into v_track from public.track_pool tp
    where public._pool_match(tp, v_room.swedish_mode, v_room.year_bands, v_room.genres)
      and not exists (select 1 from public.round_tracks rt
                      where rt.room_id = p_room_id and rt.pool_id = tp.id)
      and (tp.preview_url is not null
           or tp.preview_checked_at is null
           or tp.preview_checked_at < now() - interval '7 days')
    order by random() limit 1;

  -- Steg 2: släpp kravet på ospelad, behåll bortsorteringen av ohittbara.
  if v_track.id is null then
    select tp.* into v_track from public.track_pool tp
      where public._pool_match(tp, v_room.swedish_mode, v_room.year_bands, v_room.genres)
        and (tp.preview_url is not null
             or tp.preview_checked_at is null
             or tp.preview_checked_at < now() - interval '7 days')
      order by random() limit 1;
  end if;

  -- Steg 3: smal pott där allt är markerat – hellre en osäker låt än inget.
  if v_track.id is null then
    select tp.* into v_track from public.track_pool tp
      where public._pool_match(tp, v_room.swedish_mode, v_room.year_bands, v_room.genres)
      order by random() limit 1;
  end if;
  if v_track.id is null then raise exception 'Låtpotten är tom'; end if;

  -- Cacheträff: starta direkt, utan att fråga iTunes. Katalograder har ingen
  -- hållbarhetsgräns – de är inte hittade via sökningen och kan inte
  -- verifieras om den vägen.
  if v_track.preview_url is not null
     and (v_track.preview_source = 'catalog'
          or v_track.preview_checked_at > now() - interval '30 days') then
    update public.rounds
      set current_track_id = v_track.preview_url,
          state = 'playing',
          timer_start_at = now() + interval '3 seconds'
      where id = v_round.id;

    insert into public.round_tracks (round_id, room_id, pool_id, meta)
    values (v_round.id, p_room_id, v_track.id,
            jsonb_build_object('name', v_track.title, 'artist', v_track.artist,
                               'year', v_track.year::text))
    on conflict (round_id) do update
      set meta = excluded.meta, pool_id = excluded.pool_id;
    return;
  end if;

  v_req := net.http_get(
    url := public._itunes_search_url(public._clean_title(v_track.title) || ' ' || v_track.artist),
    timeout_milliseconds := 6000
  );

  insert into public.pending_tracks (room_id, round_id, request_id, pool_id, attempts_left, search_stage)
  values (p_room_id, v_round.id, v_req, v_track.id, 4, 1);
end $function$;

-- --- 4. bakgrundsjobbet rör inte katalograder -------------------------
create or replace function public._warm_pool_enqueue(p_batch int default 6)
returns int
language plpgsql security definer set search_path = public
as $function$
declare
  v_n   int := 0;
  v_t   record;
  v_req bigint;
  v_batch int := least(greatest(coalesce(p_batch, 6), 0), 12);
begin
  if exists (select 1 from public.pending_tracks) then
    return 0;
  end if;

  delete from public.pool_warm_queue where requested_at < now() - interval '5 minutes';

  for v_t in
    select tp.id, tp.title, tp.artist
      from public.track_pool tp
     where not exists (select 1 from public.pool_warm_queue q where q.pool_id = tp.id)
       -- Katalograder kan inte hittas av sökningen. Att söka om dem skulle
       -- bara nollställa dem igen.
       and tp.preview_source is distinct from 'catalog'
       and (
            tp.preview_checked_at is null
         or (tp.preview_url is null
             and tp.preview_checked_at < now() - interval '6 days')
         or (tp.preview_url is not null
             and tp.preview_checked_at < now() - interval '25 days')
       )
     order by tp.preview_checked_at asc nulls first
     limit v_batch
  loop
    v_req := net.http_get(
      url := public._itunes_search_url(public._clean_title(v_t.title) || ' ' || v_t.artist),
      timeout_milliseconds := 6000
    );
    insert into public.pool_warm_queue (pool_id, request_id, stage)
    values (v_t.id, v_req, 1)
    on conflict (pool_id) do update
      set request_id = excluded.request_id, stage = 1, requested_at = now();
    v_n := v_n + 1;
  end loop;

  return v_n;
end $function$;

-- --- 5. spelet får inte heller nollställa en katalograd ---------------
--  Nås normalt aldrig (katalograder är alltid cacheträff), men spärren ska
--  finnas där ändå: en enda miss får inte radera en verifierad URL.
create or replace function public._mark_unfindable(p_pool_id int)
returns void language sql security definer set search_path = public as $function$
  update public.track_pool
     set preview_url = null, preview_checked_at = now()
   where id = p_pool_id and preview_source is distinct from 'catalog';
$function$;

revoke all on function public._mark_unfindable(int) from public, anon, authenticated;
revoke all on function public._warm_pool_enqueue(int) from public, anon, authenticated;
grant execute on function public.start_random_track(uuid) to authenticated;

create index if not exists track_pool_catalog_idx
  on public.track_pool (id) where preview_source = 'catalog';

notify pgrst, 'reload schema';
