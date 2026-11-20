// lib_ascent_etl.ks -- E TAL LIVE: NEG RTN and E TAL calculated for the launch, not from tables. On the pad ops1q
// computes the earliest SSME-out time from which a TAL works (E TAL) for THIS launch (the pad, PEG's plane, the TAL
// sites, the throttles): the stage-1 predictor flies the stack from the pad to SRB separation with an SSME out at t_f
// (FSSR's boost table, as asc_s1_att; the SRB and SSME curves; drag; J2), adds the bias ASC_S1P_B (the flights'
// separation less the predictor's), and the ARD's fast-time sim (lib_ascent_ard: the TAL on two SSMEs at
// ASC_KMAX_ABORT, the OMS dump) flies the TAL to MECO; it works when MECO is at or above ASC_ETAL_HF with the ET to get
// there (ard_margin with the job's floor hf and step dt). Per site a bisection on t_f; E TAL = the earliest of the
// sites, its VI on the predicted nominal. The offline python mirror matches the full-flight truth (MRN first ok 9 s,
// ZZA 14 s; this kOS form 8.66 / 13.87 s); the predictor + B match the real flights at separation (3 m/s nominal,
// 5 m/s after a stage-1 SSME out). Vessel-free: ops1q hands it the pad state. GENERATED offline: change the
// generator, not this file.
@LAZYGLOBAL OFF.

// ASC_S1P_*: the stage-1 predictor's constants (E TAL live), GENERATED offline from the python stack and the flights'
// separations (B). Do not edit: re-run the generator. CD_M is fitted on 9 ascent logs (the vehicle's drag is ~0.6x the
// stack model's at Mach 1.1 and 0.44x at 2), the Isp keys x (1 - e) (the model's thrust along the path is 1.6 % high),
// and B on 5 nominal flights, so B carries no drag or thrust error into the in-flight starts: the predicted separation
// VI within 6 m/s of the flown one from every start MET 0..78.
GLOBAL ASC_S1P_SRB_C IS LIST(LIST(0, 0.13950000000000001, 7.1346999999999996, 7.1346999999999996), LIST(0.0065199999999999998, 0.18609999999999999, 12.3147, 12.3147), LIST(0.02266, 0.41860000000000003, 8.7172999999999998, 8.7172999999999998), LIST(0.057750000000000003, 0.63260000000000005, 2.1069, 2.1069), LIST(0.17721000000000001, 0.74429999999999996, 0.69520000000000004, 0.69520000000000004), LIST(0.31201000000000001, 0.80940000000000001, -0.085800000000000001, -0.085800000000000001), LIST(0.39398, 0.72570000000000001, -1.2082999999999999, -1.2082999999999999), LIST(0.46600000000000003, 0.62329999999999997, -0.45079999999999998, -0.45079999999999998), LIST(0.51778999999999997, 0.66979999999999995, 1.4043000000000001, 1.4043000000000001), LIST(0.61838000000000004, 0.83730000000000004, 1.2126999999999999, 1.2126999999999999), LIST(0.79005000000000003, 1, 0.51649999999999996, 0.51649999999999996), LIST(0.89580000000000004, 0.98060000000000003, -0.13869999999999999, -0.13869999999999999), LIST(1, 0.97089999999999999, -0.093200000000000005, -0.093200000000000005)).   // the SRB thrust (x its max flow) on the SolidFuel fraction
GLOBAL ASC_S1P_SRB_I IS LIST(LIST(0, 175.72722973149703, 0, 0), LIST(1, 158.67906565306819, -17.048164078428822, -17.048164078428822), LIST(7, 0.00052130879081252652, -26.446424057379563, -26.446424057379563)).   // the SRB Isp (s) on the pressure (atm), x (1 - 0.0164): the thrust along the path (refit_b 10-23)
GLOBAL ASC_S1P_SS_I IS LIST(LIST(0, 235.63157344726193, 0, 0), LIST(1, 190.79901743738469, -44.832556009877251, -44.832556009877251), LIST(3, 13.032719770313159, -88.883148833535756, -88.883148833535756)).   // the SSME Isp (s) on the pressure (atm), x (1 - 0.0164): the thrust along the path (refit_b 10-23)
GLOBAL ASC_S1P_SRB_MD IS 2.0797690545696925.   // t/s: one SRB's flow at curve 1
GLOBAL ASC_S1P_SRB_CAP IS 125.0025.   // t: one SRB's SolidFuel capacity
GLOBAL ASC_S1P_NSRB IS 2.
GLOBAL ASC_S1P_SDRY IS 21.827369999999998.   // t: one SRB's mass less its SolidFuel
GLOBAL ASC_S1P_SSMD IS 0.69723457875181438.   // t/s: three SSMEs at KSP throttle 1
GLOBAL ASC_S1P_AREF IS 58.299999999999997.   // m2: stage 1's frontal area
GLOBAL ASC_S1P_CDM IS LIST(0, 0.38136783309623518, 0.29999999999999999, 0.38136783309623518, 0.59999999999999998, 0.31413692391512821, 0.80000000000000004, 0.43695530782890218, 0.94999999999999996, 0.46690624167428552, 1.1000000000000001, 0.42960041392488524, 1.25, 0.38706034039559062, 1.5, 0.33555671135769916, 2, 0.24697610248567836, 2.5, 0.21830923344716208, 3, 0.18964236440864585, 4, 0.16318063914232317, 6, 0.14553948896477473, 10, 0.13230862633161336).   // CD on Mach (x, y pairs), fitted on the flights
GLOBAL ASC_S1P_ATM_PER_PA IS 9.8692326671601302e-06.
GLOBAL ASC_S1P_ATM IS LIST(
  101325, 1.2013689740317286, 343.62449484775993, 94283.277090575022, 1.1302274595123656, 341.74205096785977,
  87664.086943679984, 1.0626182911233673, 339.84918081388901, 81447.447431384644, 0.99841623286612591, 337.94570900339335,
  75613.376425758892, 0.93749032474176375, 336.03145518759891, 70141.891798872472, 0.87970355200627071, 334.10623385221396,
  65013.011422795229, 0.82491249121835741, 332.16985410783849, 60206.753169596952, 0.77296693115776671, 330.22211946931162,
  55702.97171564804, 0.72465495165483784, 328.04812861741232, 51480.648290912235, 0.68096405233647384, 325.3298587276845,
  47524.446770233197, 0.63936202208254977, 322.58868580710481, 43820.525101070678, 0.59976821899267196, 319.82402029413583,
  40355.04123088449, 0.56209630058006887, 317.03524692626792, 37114.153107134443, 0.52625371114632213, 314.22172314310268,
  34084.018677280299, 0.49214111280806605, 311.38277735954631, 31251.809302599006, 0.45914452025908575, 308.6930801462716,
  28621.368999433867, 0.42675772248194799, 306.42099692134065, 26185.957165126012, 0.39634411946380299, 304.1319392859113,
  23932.58998645694, 0.36779499038067837, 301.82552146073971, 21848.283650208108, 0.34099483905743289, 299.50134280870094,
  19920.054343160995, 0.31582085774203505, 297.15898702133154, 18134.918252097075, 0.29214233914650239, 294.7980212472026,
  16491.671609597317, 0.26733601294375009, 293.87836837781845, 14993.138759569243, 0.24439948876095327, 293.06243095453976,
  13627.24579117284, 0.22337999070721817, 292.2442159936727, 12381.85673752675, 0.20410989346406291, 291.42370381746719,
  11244.835631749624, 0.1864177690447156, 290.6008744717634, 10204.046506960109, 0.17012827840962649, 289.77570772048972,
  9254.8921853124139, 0.15416875249252884, 289.9022038917962, 8397.246037424924, 0.13968892093952193, 290.10250033583168,
  7622.3808968877165, 0.12662418089666613, 290.30265861361374, 6921.5271251570639, 0.1148232063342509, 290.50267898229527,
  6285.9150836892431, 0.10413550332270044, 290.70256169812512, 5706.7751339405268, 0.094411404323183706, 290.9023070164522,
  5180.5050976169932, 0.085256606270821156, 291.66616161895058, 4706.1919877408927, 0.077042886725298451, 292.43716207245404,
  4278.6521003295384, 0.06967691244639701, 293.20613477606162, 3892.7005181086088, 0.063061434941551392, 293.97309599834642,
  3543.1523238037857, 0.05710122236215761, 294.7380617971408, 3224.8226001407493, 0.051703007485117837, 295.50104802335977,
  2935.031650570565, 0.046804154905399742, 296.29764834226609, 2673.339811793152, 0.042402589600518924, 297.09470176386651,
  2436.9776848339429, 0.038447564300878277, 297.88962270558682, 2223.164387231036, 0.034888336209598844, 298.6824280572788,
  2029.1190365225286, 0.03167523292064367, 299.47313448486636, 1852.0607502465195, 0.028759624345608997, 300.2617584344714,
  1690.0500167681932, 0.026084752102976769, 301.17605207694879, 1543.3660513583202, 0.023668697823156129, 302.14214156227723,
  1410.6541599040604, 0.021496212386218932, 303.10515242444541, 1290.424476035095, 0.019540129178424955, 304.06511352976656,
  1181.1871333811055, 0.017773962328259865, 305.02205328910452, 1081.4522655717724, 0.016171885520989783, 305.97599966783685,
  989.79727911739428, 0.014711926862381038, 306.90386894616898, 906.26127956495043, 0.013395035179512521, 307.76469412726345,
  830.52173102145605, 0.012207370302980552, 308.62311826034909, 761.79719333569062, 0.011135367997463605, 309.47916132812389,
  699.30622635643408, 0.010165762123488553, 310.33284303768454, 642.26738993246613, 0.0092855764932389239, 311.18418282581854,
  589.89924391256625, 0.0084821169919223321, 312.03319986416739, 541.62419149535015, 0.0077415954693489846, 312.96646470165149,
  497.67465104686028, 0.0070686451924735789, 313.95592459638203, 457.72606398625561, 0.0064605835385641037, 314.94227646268843,
  421.36885749444934, 0.0059104556773722531, 315.92554911382473, 388.19345875235513, 0.0054114786035272932, 316.9057709151258,
  357.79029494088644, 0.0049570358636759878, 317.8829697936705, 329.74979324095659, 0.0045406724764020306, 318.85717324767757,
  303.80498671442297, 0.0041577602024426641, 319.83923960665578, 280.12769855348222, 0.003810220207336516, 320.82411341864236,
  258.54463054215466, 0.0034952267082603477, 321.80597273844779, 238.84519991071247, 0.0032093588005221458, 322.78484524669494,
  220.81882388942779, 0.002949277949707512, 323.76075820606707, 204.25491970857274, 0.0027117255270601368, 324.73373847010305,
  188.94290459841946, 0.0024935204328872806, 325.70381249175665, 174.69873175366777, 0.0022943347908042908, 326.49797712510878,
  161.59911228330083, 0.0021154671479917853, 327.02455006887647, 149.59689706894929, 0.0019520667860493186, 327.5502768543862,
  138.58872442735375, 0.0018026409124162058, 328.07516139621805, 128.47123267525478, 0.0016657157641517392, 328.59920757744425,
  119.14106012939295, 0.0015398363057933322, 329.12241924997892, 110.49484510650882, 0.0014235659329284835, 329.64480023492411,
  102.42922592334295, 0.0013154861813549047, 330.16635432291002, 94.908224575622029, 0.0012203733817457037, 329.9662913452396,
  87.972695425945716, 0.0011333883676835244, 329.64659028946505, 81.573743872956769, 0.0010529914817692912, 329.32657889318727,
  75.660807072788799, 0.00097856726824677664, 329.00625624248386, 70.183322181575448, 0.00090949546595278587, 328.68562141898724,
  65.090726355450315, 0.00084515096132855086, 328.36467349985446, 60.332456750546989, 0.00078490374087801875, 328.04341155773608,
  55.86142215635838, 0.00072912151162983952, 327.50659692464342, 51.705959013640474, 0.00067971043384120334, 326.34152949332361,
  47.864670198832933, 0.00063374719073800649, 325.17228734603754, 44.308852887451827, 0.00059092404685757288, 323.99882544881734,
  41.009804255013272, 0.0005509242690308956, 322.82109794859321, 37.938821477033365, 0.00051342179507134602, 321.63905815220215,
  35.067201729028177, 0.00047808088772346606, 320.45265850470082, 32.366242186513837, 0.00044455577310106745, 319.2618505669526,
  29.839625797398853, 0.00041277717253097526, 318.12871005333227, 27.515520384442105, 0.00038334190029123397, 317.00034424050256,
  25.375222646192892, 0.00035606293825340404, 315.8679481099382, 23.39940438785467, 0.00033071391548497147, 314.73147786245119,
  21.568737414630913, 0.00030706186203142071, 313.59088890627214, 19.863893531725083, 0.00028486696673093672, 312.44613583678944,
  18.265544544340649, 0.00026388232427360147, 311.29717241561661, 16.773973226264715, 0.00024408988195031135, 310.17521948033772,
  15.408660025900925, 0.00022585040458312066, 309.05517084789506, 14.157243016688742, 0.00020902573245358159, 307.9310484491894,
  13.006675564328162, 0.00019345309273212876, 306.8028073738372, 11.943911034519179, 0.00017896487944729899, 305.67040188310648,
  10.955902792961776, 0.00016538847277117313, 304.53378538835199, 10.029836877098901, 0.00015253417442614867, 303.4082399293377,
  9.175107338756602, 0.00014046922159019885, 302.39806169828404, 8.3965907661779351, 0.00012941636465079755, 301.38449755506127,
  7.6856921144809434, 0.00011926282520769529, 300.3675132345121, 7.0338163387836747, 0.00010989274403461309, 299.34707388938511,
  6.4323683942041772, 0.0001011870751543765, 298.32314407639728, 5.8727532358604959, 9.3023475513710974e-05, 297.29568774186441,
  5.3517395496455702, 8.5279463104231647e-05, 296.40755585409386, 4.8790759880485997, 7.8180373146541701e-05, 295.58605116669395,
  4.4502570883663042, 7.1708292337587296e-05, 294.76225768923393, 4.0595736817221733, 6.5781297729849319e-05, 293.93615565677163,
  3.7013165992397012, 6.0315611308612476e-05, 293.1077250273035, 3.3697766720423834, 5.5225547205721017e-05, 292.27694547625907,
  3.060933565774274, 5.0432356929803795e-05, 291.49850615469393, 2.7810757146508487, 4.6048472501260784e-05, 290.77884435695427,
  2.5285035773123874, 4.207495991077007e-05, 290.05739677425834, 2.2995312025639882, 3.8456339398994321e-05, 289.33415020370802,
  2.0904726392107476, 3.5136014790319946e-05, 288.60909127658374, 1.8976419360577625, 3.2056245264879098e-05, 287.88220645542316,
  1.7184203299752645, 2.9165281465602083e-05, 287.20740242676192, 1.5566700545517207, 2.6533896605123281e-05, 286.59049554953293,
  1.4112822645009473, 2.4159842741806285e-05, 285.97225798404133, 1.2799164125424785, 2.2006233757127291e-05, 285.35268099996182,
  1.160231951395849, 2.0035539313831191e-05, 284.73175577215972, 1.049888333780594, 1.8209570731361122e-05, 284.10947337923972,
  0.94781157465937227, 1.6512391315506552e-05, 283.47843865412608, 0.85638595489198943, 1.4986824704932743e-05, 282.8420448543103,
  0.774479134824273, 1.36147839863898e-05, 282.20421594380554, 0.70061541145743689, 1.2372303229390131e-05, 281.56494216449499,
  0.63331908179269525, 1.1234978714949606e-05, 280.92421364724504, 0.57111444283126245, 1.017795889335453e-05, 280.28202041012901,
  0.51431951118849462, 9.1926587228671577e-06, 279.87231846880763, 0.46378084204638476, 8.313403972982146e-06, 279.46728394606214,
  0.4185852320583725, 7.5250879403841363e-06, 279.06166134327992, 0.37781861552536905, 6.8120260908564407e-06, 278.65544835229099,
  0.34056692674828615, 6.1583503123293556e-06, 278.24864264769855, 0.30611733280925219, 5.5497911909258293e-06, 277.8879102642677,
  0.27532682913245876, 5.0023029811806358e-06, 277.58965962701967, 0.24798105967480191, 4.5151763547015355e-06, 277.29108750753159,
  0.22351975094203455, 4.0785789600521028e-06, 276.99219339275999, 0.20138262943990939, 3.6825933453138922e-06, 276.69297676632169,
  0.18100942167417938, 3.3172160336459725e-06, 276.39343710846958, 0.1624718092757223, 2.9791544322532879e-06, 276.31630596193207,
  0.14609674280329207, 2.680201176483623e-06, 276.24891704185421, 0.13154926036333117, 2.4145001335910281e-06, 276.18151178498334,
  0.11849325130875198, 2.1759279267104265e-06, 276.11409003858279, 0.10659260499246682, 1.9583492089865886e-06, 276.04665164976404,
  0.09286870991937797, 1.7063959222420883e-06, 276.03160975646364, 0.06697365412455579, 1.230315959891195e-06, 276.06266916289269,
  0.036314959519760652, 6.6696112349054212e-07, 276.09372507037716, 0.010715962634929679, 1.9676527691050123e-07, 276.12477748675809,
  0, 0, 276.15582641987305).   // every 500 m to 80 km: p Pa, rho kg/m3, a m/s
GLOBAL ASC_S1P_B IS LIST(-0.12936373220521205, 334.39267092481583, -877.46196203319994, 425.03203876954376, 14.791754014633733, -22.221179541339673, 2.3965927051312605, 0.63758991082147531).   // 5 flights less the model at sep: t s; r up dn cr m; v up dn cr m/s; ET t
GLOBAL ASC_S1P_MC IS 36.250500000000002.   // t: the core less the ET's propellant (stage 2's MASS_MIN; the pad search's)
GLOBAL ASC_S1P_ET IS 194.25067192060095.   // t: the ET's propellant on the pad (the predictor's; B is relative to it)
GLOBAL ASC_S1P_F1 IS 546.   // kN: one SSME at KSP throttle 1 in vacuum (the TAL flights': ard.Model md3 / 3 x vex)
GLOBAL ASC_S1P_VEX IS 2349.281074.   // m/s: the SSMEs' exhaust speed in vacuum (ard.Model vex)

// ---- E TAL live: THE STAGE-1 PREDICTOR (the offline predictor's mirror). From a stage-1 state to SRB separation, an
// SSME out at teo (the flow x 2/3, KABT from it): the SRB thrust on its FloatCurve keys, the Isp curves on the
// pressure, the boost throttle steps (asc_s1_thr's), drag q A_REF CD_M(Mach), asc_grav, kOS's law (asc_s1_att's
// tables); RK4 at dt, the steps split at teo, T_CNS and the tower clear (linear in V_rel), the last one ending at the
// burnout (sf = 0). The constants (ASC_S1P_*) are the python stack's.

// KSP's FloatCurve (A.Curve): the cubic Hermite on keys LIST(t, v, in, out), clamped at both ends
FUNCTION ard_herm {
  PARAMETER k, x.
  IF x <= k[0][0] { RETURN k[0][1]. }
  IF x >= k[k:LENGTH - 1][0] { RETURN k[k:LENGTH - 1][1]. }
  LOCAL i IS 0.
  UNTIL x < k[i + 1][0] { SET i TO i + 1. }
  LOCAL a IS k[i].
  LOCAL b IS k[i + 1].
  LOCAL d IS b[0] - a[0].
  LOCAL s IS (x - a[0]) / d.
  LOCAL s2 IS s * s.
  LOCAL s3 IS s2 * s.
  RETURN (2 * s3 - 3 * s2 + 1) * a[1] + (s3 - 2 * s2 + s) * d * a[3] + (3 * s2 - 2 * s3) * b[1] + (s3 - s2) * d * b[2].
}

// the air on the 500 m table (p Pa, rho kg/m3, a m/s): the sound speed linear, the pressure and density log-linear
FUNCTION ard_air {
  PARAMETER hgt.
  LOCAL T IS ASC_S1P_ATM.
  LOCAL n IS T:LENGTH / 3.
  IF hgt >= (n - 1) * 500 { RETURN LIST(0, 0, T[T:LENGTH - 1]). }
  LOCAL x IS MAX(hgt, 0) / 500.
  LOCAL i IS MIN(FLOOR(x), n - 2).
  LOCAL f IS x - i.
  LOCAL p0 IS T[3 * i].
  LOCAL p1 IS T[3 * i + 3].
  LOCAL r0 IS T[3 * i + 1].
  LOCAL r1 IS T[3 * i + 4].
  LOCAL p IS p0 + f * (p1 - p0).
  IF p0 > 0 AND p1 > 0 { SET p TO p0 * (p1 / p0) ^ f. }
  LOCAL rq IS r0 + f * (r1 - r0).
  IF r0 > 0 AND r1 > 0 { SET rq TO r0 * (r1 / r0) ^ f. }
  RETURN LIST(p, rq, T[3 * i + 2] + f * (T[3 * i + 5] - T[3 * i + 2])).
}

// A.interp: y at x on the (x, y) pairs (clamped)
FUNCTION ard_lin {
  PARAMETER tb, x.
  IF x <= tb[0] { RETURN tb[1]. }
  FROM { LOCAL i IS 2. } UNTIL i >= tb:LENGTH STEP { SET i TO i + 2. } DO {
    IF x <= tb[i] { RETURN tb[i - 1] + (x - tb[i - 2]) / (tb[i] - tb[i - 2]) * (tb[i + 1] - tb[i - 1]). }
  }
  RETURN tb[tb:LENGTH - 1].
}

// the thrust direction: up before the tower clear, then asc_s1_att's pitch / heading (the tail-off from tc <> -99)
FUNCTION ard_s1_att {
  PARAMETER j, t, rh, vrel, hgt.
  IF NOT j["po"] { RETURN rh. }
  LOCAL x IS asc_vref(vrel, hgt).
  LOCAL i IS j["i"].
  UNTIL i >= ASC_PPOLY:LENGTH - 2 OR x < ASC_PPOLY[i + 1] { SET i TO i + 1. }
  LOCAL th IS asc_tab(ASC_PPOLY, ASC_THET, i, x).
  LOCAL ps IS asc_tab(ASC_PPOLY, ASC_PSI, i, x) + j["dpsi"].
  IF j["south"] { SET ps TO 180 - ps. }
  IF t >= ASC_T_CNS_PITCH_RATE AND j["tc"] <> -99 {
    SET th TO 4 * ARCTAN(j["tc"] + 0.25 * ASC_THETC_DOT_NOM_RAD * (t - ASC_T_CNS_PITCH_RATE)).
  }
  LOCAL e IS V(-rh:Y, rh:X, 0):NORMALIZED.
  LOCAL d IS COS(ps) * VCRS(rh, e) + SIN(ps) * e.
  RETURN COS(th) * d + SIN(th) * rh.
}

// the derivatives: LIST(dr, dv, dsf, det)
FUNCTION ard_s1_f {
  PARAMETER j, t, rr, vv, sf, et, eo.
  LOCAL rm IS rr:MAG.
  LOCAL rh IS rr / rm.
  LOCAL hgt IS rm - ASC_R.
  LOCAL wv IS V(vv:X + ASC_ARD_W * rr:Y, vv:Y - ASC_ARD_W * rr:X, vv:Z).
  LOCAL vrel IS wv:MAG.
  LOCAL ai IS ard_air(hgt).
  LOCAL patm IS ai[0] * ASC_S1P_ATM_PER_PA.
  LOCAL m IS j["mc"] + et + ASC_S1P_NSRB * (j["sdry"] + MAX(sf, 0)).
  LOCAL u IS ard_s1_att(j, t, rh, vrel, hgt).
  LOCAL md1 IS 0.
  IF sf > 0 { SET md1 TO ASC_S1P_SRB_MD * ard_herm(ASC_S1P_SRB_C, sf / ASC_S1P_SRB_CAP). }
  LOCAL fs IS ASC_S1P_NSRB * md1 * ard_herm(ASC_S1P_SRB_I, patm) * 9.80665.
  LOCAL k IS j["knom"].
  IF eo { SET k TO j["kabt"]. } ELSE {
    FROM { LOCAL qq IS 0. } UNTIL qq >= MIN(ASC_QPOLY:LENGTH, 4) STEP { SET qq TO qq + 1. } DO {
      IF vrel >= ASC_QPOLY[qq] { SET k TO ASC_THROT[qq]. }
    }
  }
  LOCAL mds IS k / 100 * ASC_PL_TO_KSP * j["ssmd"].
  IF eo { SET mds TO mds * 2 / 3. }
  LOCAL a IS (fs + mds * ard_herm(ASC_S1P_SS_I, patm) * 9.80665) / m * u + asc_grav(rr).
  IF ai[1] > 0 AND vrel > 1e-6 {
    SET a TO a - 0.5 * ai[1] * vrel * ASC_S1P_AREF * ard_lin(ASC_S1P_CDM, vrel / ai[2]) / 1000 / m * wv.
  }
  RETURN LIST(vv, a, -md1, -mds).
}

FUNCTION ard_s1_rk4 {
  PARAMETER j, t, y, h, eo.
  LOCAL k1 IS ard_s1_f(j, t, y[0], y[1], y[2], y[3], eo).
  LOCAL k2 IS ard_s1_f(j, t + h / 2, y[0] + h / 2 * k1[0], y[1] + h / 2 * k1[1], y[2] + h / 2 * k1[2], y[3] + h / 2 * k1[3], eo).
  LOCAL k3 IS ard_s1_f(j, t + h / 2, y[0] + h / 2 * k2[0], y[1] + h / 2 * k2[1], y[2] + h / 2 * k2[2], y[3] + h / 2 * k2[3], eo).
  LOCAL k4 IS ard_s1_f(j, t + h, y[0] + h * k3[0], y[1] + h * k3[1], y[2] + h * k3[2], y[3] + h * k3[3], eo).
  RETURN LIST(y[0] + h / 6 * (k1[0] + 2 * k2[0] + 2 * k3[0] + k4[0]), y[1] + h / 6 * (k1[1] + 2 * k2[1] + 2 * k3[1] + k4[1]),
    y[2] + h / 6 * (k1[2] + 2 * k2[2] + 2 * k3[2] + k4[2]), y[3] + h / 6 * (k1[3] + 2 * k2[3] + 2 * k3[3] + k4[3])).
}

FUNCTION ard_s1_vrel {
  PARAMETER y.
  RETURN V(y[1]:X + ASC_ARD_W * y[0]:Y, y[1]:Y - ASC_ARD_W * y[0]:X, y[1]:Z):MAG.
}

// a new prediction from (t, r, v, sf, et), past the tower clear po, the tail-off tangent tc (-99 none), the SSME out at
// teo (-1 none); vh = LEXICON(mc, sdry, ssmd, knom, kabt, dpsi, south)
FUNCTION ard_s1_new {
  PARAMETER t, rr, vv, sf, et, po, tc, teo, dt, vh.
  RETURN LEXICON("t", t, "y", LIST(rr, vv, sf, et), "po", po, "tc", tc, "teo", teo, "dt", dt, "i", 0, "n", 0, "done", FALSE,
    "mc", vh["mc"], "sdry", vh["sdry"], "ssmd", vh["ssmd"], "knom", vh["knom"], "kabt", vh["kabt"], "dpsi", vh["dpsi"],
    "south", vh["south"]).
}

// one RK4 step; TRUE once at the separation (j["t"], j["y"])
FUNCTION ard_s1_step {
  PARAMETER j.
  IF j["done"] { RETURN TRUE. }
  LOCAL t IS j["t"].
  LOCAL y IS j["y"].
  LOCAL eo IS j["teo"] >= 0 AND t >= j["teo"] - 1e-9.
  LOCAL h IS j["dt"].
  IF j["teo"] >= 0 AND t + 1e-9 < j["teo"] AND j["teo"] < t + h - 1e-9 { SET h TO j["teo"] - t. }
  IF t + 1e-9 < ASC_T_CNS_PITCH_RATE AND ASC_T_CNS_PITCH_RATE < t + h - 1e-9 { SET h TO ASC_T_CNS_PITCH_RATE - t. }
  LOCAL y1 IS ard_s1_rk4(j, t, y, h, eo).
  IF y1[2] <= 0 {                                   // the burnout inside: the step shortened to sf = 0 (secant)
    LOCAL lo IS 0.
    LOCAL flo IS y[2].
    LOCAL hi IS h.
    LOCAL fhi IS y1[2].
    LOCAL hm IS h.
    LOCAL ym IS y1.
    FROM { LOCAL qq IS 0. } UNTIL qq >= 30 STEP { SET qq TO qq + 1. } DO {
      SET hm TO hi - fhi * (hi - lo) / (fhi - flo).
      SET ym TO ard_s1_rk4(j, t, y, hm, eo).
      IF ABS(ym[2]) < 1e-7 { BREAK. }
      IF ym[2] > 0 { SET lo TO hm. SET flo TO ym[2]. } ELSE { SET hi TO hm. SET fhi TO ym[2]. }
    }
    SET j["t"] TO t + hm.
    SET j["y"] TO LIST(ym[0], ym[1], 0, ym[3]).
    SET j["n"] TO j["n"] + 1.
    SET j["done"] TO TRUE.
    RETURN TRUE.
  }
  IF NOT j["po"] {                                  // the tower clear inside: the step shortened (linear in V_rel)
    LOCAL v0 IS ard_s1_vrel(y).
    LOCAL v1 IS ard_s1_vrel(y1).
    IF v1 >= ASC_PPOLY[1] {
      LOCAL hc IS h.
      IF v1 > v0 { SET hc TO h * (ASC_PPOLY[1] - v0) / (v1 - v0). }
      SET y1 TO ard_s1_rk4(j, t, y, hc, eo).
      SET h TO hc.
      SET j["po"] TO TRUE.
    }
  }
  SET t TO t + h.
  SET j["t"] TO t.
  SET j["y"] TO y1.
  SET j["n"] TO j["n"] + 1.
  IF j["po"] {                                      // the table's segment at the step's end (it only climbs)
    LOCAL x IS asc_vref(ard_s1_vrel(y1), y1[0]:MAG - ASC_R).
    UNTIL j["i"] >= ASC_PPOLY:LENGTH - 2 OR x < ASC_PPOLY[j["i"] + 1] { SET j["i"] TO j["i"] + 1. }
    IF j["tc"] = -99 AND t >= ASC_T_CNS_PITCH_RATE - 1e-9 { SET j["tc"] TO TAN(asc_tab(ASC_PPOLY, ASC_THET, j["i"], x) / 4). }
  }
  RETURN FALSE.
}

// ---- E TAL live: THE SEARCH (n21/etal_live.py's mirror), run on the pad: per TAL site the earliest SSME-out time whose
// TAL from the predicted separation (ard_s1_*, + the bias ASC_S1P_B) clears ASC_ETAL_HF at MECO with the ET to do it
// (ard_margin's TAL test with the job's floor hf); the bisection to ASC_ETAL_TOL, then linear. E TAL = the earliest over
// the sites; its VI on the predicted nominal.
// THE FAST SEARCH: (1) a trial's stage 1 starts from the nominal's state at its last step at or before the SSME-out time
// (E["snap"]; ard_s1_step splits only the step holding teo, so bit for bit the flight from the pad); (2) a seed
// (E["sv"]: the tables' E TAL VI, for the first site; the earliest site found so far for the others) is tried first,
// the bracket widened from it by ASC_ETAL_SEED_DT doubling to the sign change (0 / ASC_ETAL_HI its ends), then the
// bisection; no seed: the ends 0 / HI.
GLOBAL ASC_ETAL_ON IS TRUE.      // E TAL live (with ASC_ARD_ON); FALSE: the tables' mark (lib_ascent_abr)
GLOBAL ASC_ETAL_MAXU IS 4.       // units a main-loop pass at most (ops1q asc_etl_work; the first always)
GLOBAL ASC_ETAL_TOL IS 0.05.     // s: the bisection's last bracket
GLOBAL ASC_ETAL_HF IS 80000.     // m: a 1EO TAL's MECO floor (margins.tal_test: h >= 80 km at MECO)
GLOBAL ASC_ETAL_HI IS 79.        // s: the latest SSME-out time searched (SRB sep ~79.5 s)
GLOBAL ASC_ETAL_SEED_ON IS TRUE.   // the seed (FALSE: the ends 0 / HI)
GLOBAL ASC_ETAL_SEED_DT IS 1.      // s, the first widening from the seed (then doubled)
GLOBAL ASC_ETAL_DT IS 4.         // s: the TAL flights' step (etal_live's; ASC_ARD_DT's 8 puts E TAL ~1 s late, n21/scan_e)

FUNCTION ard_et_s1 {
  PARAMETER p0, teo, vh.
  // a state in flight (ops1q asc_s1l_go) carries p0[5] past the tower clear and p0[6] the tail-off tangent
  // (asc_s1_att's "clear" / "thetc_cns"); the pad's five entries start before the tower clear, no tangent, as before
  IF p0:LENGTH > 6 { RETURN ard_s1_new(p0[0], p0[1], p0[2], p0[3], p0[4], p0[5], p0[6], teo, 2, vh). }
  RETURN ard_s1_new(p0[0], p0[1], p0[2], p0[3], p0[4], FALSE, -99, teo, 2, vh).
}

// a new search from the pad p0 = LIST(t, rr, vv, sf, et); vh the vehicle (ard_s1_new's); sn = LEXICON(mc, res, m); tls
// the sites' targets (asc_tal_lex); iy PEG's plane
// (or from a state in flight, p0 = LIST(t, rr, vv, sf, et, po, tc): ard_et_s1)
FUNCTION ard_et_new {
  PARAMETER p0, vh, sn, tls, iy.
  RETURN LEXICON("p0", p0, "vh", vh, "sn", sn, "tls", tls, "iy", iy, "ks", tls:KEYS, "si", 0, "lo", 0, "hi", ASC_ETAL_HI,
    "mlo", 0, "mhi", 0, "bs", 0, "tf", 0, "ph", "nom", "s1", ard_et_s1(p0, -1, vh), "job", 0, "vt", LIST(), "tb", LEXICON(),
    "etal", -1, "vi", -1, "done", FALSE, "n", 0, "snap", LIST(), "sv", -1, "st", -1, "dd", 0, "dir", 0).
}

// the predicted separation + B (the local frame there): LIST(t, rr, vv, et)
FUNCTION ard_et_sep {
  PARAMETER j.
  LOCAL rr IS j["y"][0].
  LOCAL vv IS j["y"][1].
  LOCAL ru IS rr:NORMALIZED.
  LOCAL hh IS VCRS(rr, vv):NORMALIZED.
  LOCAL dn IS VCRS(hh, ru).
  LOCAL B IS ASC_S1P_B.
  RETURN LIST(j["t"] + B[0], rr + B[1] * ru + B[2] * dn + B[3] * hh, vv + B[4] * ru + B[5] * dn + B[6] * hh, j["y"][3] + B[7]).
}

// the TAL job (ard_lv_job's) from the separation sp for site k: PEG cold, the steering along the horizontal speed
FUNCTION ard_et_job {
  PARAMETER E, k, sp.
  LOCAL ts IS sp[0].
  LOCAL ru IS sp[1]:NORMALIZED.
  LOCAL hz IS (sp[2] - VDOT(sp[2], ru) * ru):NORMALIZED.
  LOCAL sn IS E["sn"].
  LOCAL j IS ard_new(LEXICON("md", "TAL", "tl", E["tls"][k], "e", 2, "K", ASC_KMAX_ABORT, "t", ts, "r", sp[1], "v", sp[2],
    "et", sp[3], "mc", sn["mc"], "res", sn["res"], "iy", E["iy"], "steer", LIST(hz, V(0, 0, 0), ts),
    "o", LIST(ts + ASC_TAL_OMS_DELAY, ts + ASC_TAL_OMS_DELAY + ASC_TAL_DUMP / ASC_ARD_MDO), "m", sn["m"], "tr", FALSE,
    "ts", -1)).
  SET j["hf"] TO ASC_ETAL_HF.
  SET j["dt"] TO ASC_ETAL_DT.
  RETURN j.
}

// the next SSME-out time to try (a new stage-1 prediction)
FUNCTION ard_et_try {
  PARAMETER E, tf.
  SET E["tf"] TO tf.
  LOCAL k IS -1.                                         // the nominal's last state at or before tf
  FROM { LOCAL i IS 0. } UNTIL i >= E["snap"]:LENGTH STEP { SET i TO i + 1. } DO {
    IF E["snap"][i]["t"] <= tf + 1e-9 AND NOT E["snap"][i]["done"] { SET k TO i. }
  }
  IF k < 0 {
    SET E["s1"] TO ard_et_s1(E["p0"], tf, E["vh"]).
  } ELSE {
    SET E["s1"] TO E["snap"][k]:COPY.
    SET E["s1"]["teo"] TO tf.
  }
  SET E["ph"] TO "s1".
}

// a site's first trial: at its seed (bs 3) when it has one in (0, HI), else at 0 (bs 0)
FUNCTION ard_et_first {
  PARAMETER E.
  SET E["lo"] TO 0.
  SET E["hi"] TO ASC_ETAL_HI.
  SET E["st"] TO -1.
  IF ASC_ETAL_SEED_ON {
    FOR k IN E["tb"]:KEYS { IF E["tb"][k] < ASC_ARD_NEVER AND (E["st"] < 0 OR E["tb"][k] < E["st"]) { SET E["st"] TO E["tb"][k]. } }
    IF E["st"] < 0 AND E["sv"] > 0 { SET E["st"] TO ard_et_tof(E["vt"], E["sv"]). }
  }
  IF E["st"] > 0 AND E["st"] < ASC_ETAL_HI {
    SET E["bs"] TO 3.
    SET E["dd"] TO ASC_ETAL_SEED_DT.
    ard_et_try(E, E["st"]).
  } ELSE {
    SET E["bs"] TO 0.
    ard_et_try(E, 0).
  }
}

// the MET at which the nominal (vt: MET, VI pairs) reaches VI vi, -1 outside it
FUNCTION ard_et_tof {
  PARAMETER vt, vi.
  FROM { LOCAL i IS 2. } UNTIL i >= vt:LENGTH STEP { SET i TO i + 2. } DO {
    IF vt[i + 1] >= vi AND vt[i - 1] < vi { RETURN vt[i - 2] + (vi - vt[i - 1]) / (vt[i + 1] - vt[i - 1]) * (vt[i] - vt[i - 2]). }
  }
  RETURN -1.
}

// a site settled at tb (100000 = never): the next site, or the end
FUNCTION ard_et_site {
  PARAMETER E, tb.
  SET E["tb"][E["ks"][E["si"]]] TO tb.
  SET E["si"] TO E["si"] + 1.
  IF E["si"] < E["ks"]:LENGTH {
    ard_et_first(E).
    RETURN.
  }
  LOCAL best IS ASC_ARD_NEVER.
  FOR k IN E["ks"] { SET best TO MIN(best, E["tb"][k]). }
  SET E["etal"] TO best.
  SET E["vi"] TO ASC_ARD_NEVER.
  LOCAL vt IS E["vt"].
  IF best < ASC_ARD_NEVER {
    SET E["vi"] TO vt[1].
    FROM { LOCAL i IS 2. } UNTIL i >= vt:LENGTH STEP { SET i TO i + 2. } DO {
      IF best <= vt[i] { SET E["vi"] TO vt[i - 1] + (best - vt[i - 2]) / (vt[i] - vt[i - 2]) * (vt[i + 1] - vt[i - 1]). BREAK. }
      SET E["vi"] TO vt[i + 1].
    }
  }
  SET E["done"] TO TRUE.
}

// one unit of the search; TRUE when done (E["etal"] s MET, E["vi"] m/s; ASC_ARD_NEVER = never, E["tb"] per site)
FUNCTION ard_et_unit {
  PARAMETER E.
  IF E["done"] { RETURN TRUE. }
  SET E["n"] TO E["n"] + 1.
  IF E["ph"] = "nom" {                                   // the nominal's VI at its steps (for VI_b)
    LOCAL j IS E["s1"].
    IF E["vt"]:LENGTH = 0 { E["vt"]:ADD(j["t"]). E["vt"]:ADD(j["y"][1]:MAG). E["snap"]:ADD(j:COPY). }
    LOCAL fin IS ard_s1_step(j).
    E["vt"]:ADD(j["t"]).
    E["vt"]:ADD(j["y"][1]:MAG).
    E["snap"]:ADD(j:COPY).                               // the trials' starts (its y a new list each step)
    IF fin { ard_et_first(E). }
    RETURN FALSE.
  }
  IF E["ph"] = "s1" {
    IF ard_s1_step(E["s1"]) {
      SET E["job"] TO ard_et_job(E, E["ks"][E["si"]], ard_et_sep(E["s1"])).
      SET E["ph"] TO "fts".
    }
    RETURN FALSE.
  }
  IF NOT ard_unit(E["job"]) { RETURN FALSE. }
  LOCAL m IS ard_margin(E["job"]).
  IF E["bs"] >= 3 {                                      // from the seed, widening to the sign change
    IF E["bs"] = 3 {
      SET E["dir"] TO CHOOSE -1 IF m >= 0 ELSE 1.
      SET E["bs"] TO 4.
    } ELSE IF (m >= 0) <> (E["dir"] < 0) {               // the sign changed: the bracket, then the bisection
      IF m >= 0 { SET E["hi"] TO E["tf"]. SET E["mhi"] TO m. } ELSE { SET E["lo"] TO E["tf"]. SET E["mlo"] TO m. }
      SET E["bs"] TO 2.
      IF E["hi"] - E["lo"] > ASC_ETAL_TOL {
        ard_et_try(E, 0.5 * (E["lo"] + E["hi"])).
        RETURN FALSE.
      }
      ard_et_site(E, E["lo"] + (E["hi"] - E["lo"]) * (-E["mlo"]) / (E["mhi"] - E["mlo"])).
      RETURN E["done"].
    }
    IF m >= 0 { SET E["hi"] TO E["tf"]. SET E["mhi"] TO m. } ELSE { SET E["lo"] TO E["tf"]. SET E["mlo"] TO m. }
    IF E["dir"] < 0 AND E["tf"] <= 0 { ard_et_site(E, 0). RETURN E["done"]. }                 // open from the start
    IF E["dir"] > 0 AND E["tf"] >= ASC_ETAL_HI { ard_et_site(E, ASC_ARD_NEVER). RETURN E["done"]. }   // never
    LOCAL tn IS E["tf"] + E["dir"] * E["dd"].
    SET E["dd"] TO 2 * E["dd"].
    ard_et_try(E, MAX(0, MIN(ASC_ETAL_HI, tn))).
    RETURN FALSE.
  }
  IF E["bs"] = 0 {                                       // at lo: open from the start, else the end next
    IF m >= 0 { ard_et_site(E, E["lo"]). RETURN E["done"]. }
    SET E["mlo"] TO m.
    SET E["bs"] TO 1.
    ard_et_try(E, E["hi"]).
    RETURN FALSE.
  }
  IF E["bs"] = 1 {                                       // at hi: never, else bisect
    IF m < 0 { ard_et_site(E, ASC_ARD_NEVER). RETURN E["done"]. }
    SET E["mhi"] TO m.
    SET E["bs"] TO 2.
  } ELSE IF m >= 0 {
    SET E["hi"] TO E["tf"].
    SET E["mhi"] TO m.
  } ELSE {
    SET E["lo"] TO E["tf"].
    SET E["mlo"] TO m.
  }
  IF E["hi"] - E["lo"] > ASC_ETAL_TOL {
    ard_et_try(E, 0.5 * (E["lo"] + E["hi"])).
    RETURN FALSE.
  }
  ard_et_site(E, E["lo"] + (E["hi"] - E["lo"]) * (-E["mlo"]) / (E["mhi"] - E["mlo"])).
  RETURN E["done"].
}
