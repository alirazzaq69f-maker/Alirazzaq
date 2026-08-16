require "import"
import "android.widget.*"
import "android.view.*"
import "android.content.*"
import "android.os.*"
import "android.text.*"
import "android.net.Uri"
import "android.app.AlertDialog"
import "android.speech.tts.TextToSpeech"
import "java.net.URL"
import "java.io.BufferedReader"
import "java.io.InputStreamReader"
import "java.lang.Thread"
pcall(function() local SM=luajava.bindClass("android.os.StrictMode"); SM.setVmPolicy(luajava.newInstance("android.os.StrictMode$VmPolicy$Builder").build()) end)
math.randomseed(os.time())
local context=activity or service or this
local UNPACK=table.unpack or unpack
local handler=Handler(Looper.getMainLooper())
local cjson=require("cjson")

_G.mcqTtsEngineName=_G.mcqTtsEngineName or ""
_G.mcqSpeed=_G.mcqSpeed or 1.0
_G.mcqMuted=_G.mcqMuted or false
_G.mcqSyncUrl=_G.mcqSyncUrl or ""
_G.mcqLastSync=_G.mcqLastSync or "Never"

-- ===== CRASH-SAFETY WRAPPER =====
function sc(fn)
  return function(...)
    local args={...}
    local ok,err=pcall(function() fn(UNPACK(args)) end)
    if not ok then
      pcall(function()
        local dl=AlertDialog.Builder(context).setTitle("Something Went Wrong").setMessage("The plugin caught an error and stayed open instead of crashing.\n\nDetails:\n"..tostring(err)).setPositiveButton("OK",nil).create()
        if not activity then dl.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY) end
        dl.show()
      end)
    end
  end
end
function ssd(builder) pcall(function() local dl=builder.create(); if not activity then dl.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY) end; dl.show() end) end

-- ===== TTS =====
if not _G.mcqTtsEngine then
  _G.mcqTtsReady=false
  local il=TextToSpeech.OnInitListener({onInit=function(status) _G.mcqTtsReady=true end})
  if _G.mcqTtsEngineName and _G.mcqTtsEngineName~="" then
    local ok=pcall(function() _G.mcqTtsEngine=TextToSpeech(context,il,_G.mcqTtsEngineName) end)
    if not ok then _G.mcqTtsEngine=TextToSpeech(context,il) end
  else
    _G.mcqTtsEngine=TextToSpeech(context,il)
  end
end
local ttsEngine=_G.mcqTtsEngine
function switchTTSEngine(engineName)
  local il2=TextToSpeech.OnInitListener({onInit=function(status) _G.mcqTtsReady=true end})
  local newEngine=nil
  local ok=pcall(function()
    if engineName and engineName~="" then newEngine=TextToSpeech(context,il2,engineName)
    else newEngine=TextToSpeech(context,il2) end
  end)
  if ok and newEngine then
    pcall(function() ttsEngine.shutdown() end)
    ttsEngine=newEngine; _G.mcqTtsEngine=newEngine; _G.mcqTtsEngineName=engineName or ""
    return true
  end
  return false
end
function getTTSEngineList()
  local engines={}
  pcall(function()
    local el=ttsEngine.getEngines()
    for i=0,el.size()-1 do
      local e=el.get(i)
      table.insert(engines,{name=tostring(e.name),label=tostring(e.label)})
    end
  end)
  return engines
end
function showTTSEngineSelect()
  local engines=getTTSEngineList()
  if #engines==0 then
    ssd(AlertDialog.Builder(context).setTitle("TTS Engines").setMessage("Could not list additional TTS engines. Using the system default.").setPositiveButton("OK",nil))
    return
  end
  local names={}
  for i,e in ipairs(engines) do
    local mark=(e.name==_G.mcqTtsEngineName) and " (current)" or ""
    table.insert(names,e.label..mark)
  end
  ssd(AlertDialog.Builder(context).setTitle("Select TTS Engine").setItems(names,sc(function(d,pos)
    local chosen=engines[pos+1]
    local ok=switchTTSEngine(chosen.name)
    if ok then ssd(AlertDialog.Builder(context).setTitle("Changed").setMessage("Now using: "..chosen.label).setPositiveButton("OK",nil)) end
  end)).setNegativeButton("BACK",nil))
end
function speakMcq(text)
  if _G.mcqMuted then return end
  pcall(function()
    ttsEngine.setSpeechRate(_G.mcqSpeed or 1.0)
    ttsEngine.speak(tostring(text),TextToSpeech.QUEUE_FLUSH,nil,"mcq"..os.time())
  end)
end

-- ===== HTTP =====
function httpGet(urlStr,headers,cb)
  local function th()
    local rc,rs=-1,""
    pcall(function()
      local conn=URL(urlStr).openConnection()
      if headers then for k,v in pairs(headers) do conn.setRequestProperty(k,v) end end
      conn.setConnectTimeout(15000); conn.setReadTimeout(20000)
      rc=conn.getResponseCode()
      local ist=(rc==200) and conn.getInputStream() or conn.getErrorStream()
      local rd=BufferedReader(InputStreamReader(ist,"UTF-8"))
      local sb=luajava.newInstance("java.lang.StringBuilder")
      local ln=rd.readLine(); while ln~=nil do sb.append(tostring(ln)); ln=rd.readLine() end
      rd.close(); rs=tostring(sb.toString())
    end)
    local rc2,rs2=rc,rs
    handler.post(Runnable({run=function() cb(rc2,rs2) end}))
  end
  Thread(Runnable({run=th})).start()
end
function openUrlInBrowser(url)
  pcall(function()
    local it=Intent(Intent.ACTION_VIEW)
    it.setData(Uri.parse(url))
    it.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    context.startActivity(it)
  end)
end

-- ===== MCQ DATABASE =====
local MCQ_DB={}
local CATEGORIES={"Pakistan Studies","Islamiyat","General Science","Everyday Science","English","Computer & IT","Geography","Constitution & Pak Affairs","World General Knowledge","Sports","History","Current Affairs (Verified)"}

local function addMCQ(id,cat,q,opts,correct,desc,related)
  table.insert(MCQ_DB,{id=id,category=cat,question=q,options=opts,correct=correct,description=desc,related=related or {}})
end

-- ---------------- Pakistan Studies (25) ----------------
addMCQ("PS001","Pakistan Studies","Pakistan ka qayam kis din hua?",{"14 August 1947","15 August 1947","23 March 1940","11 September 1948"},1,"Pakistan 14 August 1947 ko azad mulk ke taur par wajood mein aaya.",{"PS002","PS003"})
addMCQ("PS002","Pakistan Studies","Qarardad-e-Pakistan kab pass hui?",{"23 March 1940","14 August 1947","3 June 1947","11 September 1948"},1,"Lahore mein All India Muslim League ke ijlas mein pass hui.",{"PS001","PS004"})
addMCQ("PS003","Pakistan Studies","Quaid-e-Azam ka intiqal kab hua?",{"11 September 1948","23 March 1948","14 August 1948","25 December 1948"},1,"Karachi mein intiqal hua.",{"PS001"})
addMCQ("PS004","Pakistan Studies","Qarardad-e-Pakistan waqt Muslim League president kaun the?",{"Muhammad Ali Jinnah","Liaquat Ali Khan","Allama Iqbal","Fazl-ul-Haq"},1,"Resolution Fazl-ul-Haq ne move ki thi.",{"PS002"})
addMCQ("PS005","Pakistan Studies","Pakistan ka pehla dastoor kis saal naafiz hua?",{"1956","1962","1973","1947"},1,"23 March 1956 ko naafiz hua.",{"PS006"})
addMCQ("PS006","Pakistan Studies","Mojooda dastoor kab naafiz hua?",{"1973","1956","1962","1985"},1,"Ye teesra aur mojooda dastoor hai.",{"PS005","CN001"})
addMCQ("PS007","Pakistan Studies","Qaumi tarana kisne likha?",{"Hafeez Jalandhari","Allama Iqbal","Faiz Ahmed Faiz","Ahmed Faraz"},1,"Mausiqi Ahmed Ghulamali Chagla ne banayi.",{"PS001"})
addMCQ("PS008","Pakistan Studies","Minar-e-Pakistan kahan hai?",{"Lahore","Karachi","Islamabad","Peshawar"},1,"Iqbal Park mein waqai hai.",{"PS002"})
addMCQ("PS009","Pakistan Studies","Rakbe ke lihaz se sab se bada suba?",{"Balochistan","Punjab","Sindh","KPK"},1,"Aabadi ke lihaz se Punjab bada hai.",{"GEO001"})
addMCQ("PS010","Pakistan Studies","Pakistan ke kitne sooba hain?",{"4","5","3","6"},1,"Punjab, Sindh, KPK, Balochistan.",{"PS009"})
addMCQ("PS011","Pakistan Studies","Pakistan ka qaumi phool kya hai?",{"Jasmine (Chameli)","Rose","Lily","Tulip"},1,"Chameli Pakistan ka qaumi phool hai.",{})
addMCQ("PS012","Pakistan Studies","Pakistan ka qaumi janwar kya hai?",{"Markhor","Sher","Bagh (Tiger)","Chita"},1,"Markhor ek pahaari bakri ki qisam hai.",{})
addMCQ("PS013","Pakistan Studies","Pakistan ka qaumi parinda kya hai?",{"Chakor","Mor","Kabootar","Baaz"},1,"Chakor Pakistan ka qaumi parinda hai.",{})
addMCQ("PS014","Pakistan Studies","Pakistan Resolution Day kab manaya jata hai?",{"23 March","14 August","6 September","11 September"},1,"1940 ki Qarardad-e-Pakistan ki yaad mein.",{"PS002"})
addMCQ("PS015","Pakistan Studies","Defence Day (Yaum-e-Difa) kab manaya jata hai?",{"6 September","23 March","14 August","5 February"},1,"1965 ki jang ki yaad mein manaya jata hai.",{})
addMCQ("PS016","Pakistan Studies","Kashmir Day kab manaya jata hai?",{"5 February","23 March","14 August","6 September"},1,"Kashmiri awaam se ekjehti ke izhaar ke liye.",{})
addMCQ("PS017","Pakistan Studies","Two-Nation Theory ka bunyadi tasawwur kis ne pesh kiya?",{"Allama Iqbal","Sir Syed Ahmed Khan","Quaid-e-Azam","Liaquat Ali Khan"},1,"Allama Iqbal ne 1930 ke Allahabad khutbe mein pesh kiya.",{"PS002"})
addMCQ("PS018","Pakistan Studies","Pakistan ki pehli Constituent Assembly ke pehle speaker kaun the?",{"Maulvi Tamizuddin Khan","Liaquat Ali Khan","Ghulam Muhammad","Iskander Mirza"},1,"1947 mein Maulvi Tamizuddin Khan pehle speaker bane.",{})
addMCQ("PS019","Pakistan Studies","Pakistan ka pehla Prime Minister kaun tha?",{"Liaquat Ali Khan","Muhammad Ali Jinnah","Khawaja Nazimuddin","Ghulam Muhammad"},1,"Liaquat Ali Khan Pakistan ke pehle PM bane.",{})
addMCQ("PS020","Pakistan Studies","Pakistan ke pehle Governor-General kaun the?",{"Muhammad Ali Jinnah","Liaquat Ali Khan","Ghulam Muhammad","Iskander Mirza"},1,"Quaid-e-Azam khud pehle Governor-General bane.",{"PS001"})
addMCQ("PS021","Pakistan Studies","Pakistan ka pehla Chief of Army Staff kaun tha?",{"General Ayub Khan","General Zia-ul-Haq","General Yahya Khan","General Musharraf"},1,"1951 mein General Ayub Khan pehle Pakistani C-in-C bane.",{"PS020"})
addMCQ("PS022","Pakistan Studies","Objectives Resolution kis saal pass hui?",{"1949","1947","1956","1973"},1,"Pakistan ki Constituent Assembly ne 1949 mein pass ki.",{"PS005"})
addMCQ("PS023","Pakistan Studies","Pakistan ka sab se pehla 5-year plan kis daur mein shuru hua?",{"Ayub Khan","Liaquat Ali Khan","Zia-ul-Haq","Bhutto"},1,"1950s ke aakhir mein Ayub Khan ke daur mein shuru hua.",{})
addMCQ("PS024","Pakistan Studies","Bangladesh (East Pakistan) kis saal alag hua?",{"1971","1965","1969","1958"},1,"1971 ki jang ke baad Bangladesh bana.",{"HIS002"})
addMCQ("PS025","Pakistan Studies","Simla Agreement kis saal hua?",{"1972","1971","1965","1973"},1,"Pakistan aur India ke darmiyan hua.",{"PS024"})

-- ---------------- Islamiyat (20) ----------------
addMCQ("ISL001","Islamiyat","Quran mein kitne Para hain?",{"30","28","32","27"},1,"Quran-e-Majeed 30 Para par mushtamil hai.",{"ISL002"})
addMCQ("ISL002","Islamiyat","Quran mein kitni Surahs hain?",{"114","110","120","113"},1,"Sab se choti Surah Al-Kausar hai.",{"ISL001"})
addMCQ("ISL003","Islamiyat","Sab se pehli wahi kaunsi Surah mein nazil hui?",{"Al-Alaq","Al-Fatiha","Al-Baqarah","Al-Ikhlas"},1,"Ghar-e-Hira mein nazil hui.",{"ISL001"})
addMCQ("ISL004","Islamiyat","Islam ke kitne arkan hain?",{"5","6","4","7"},1,"Kalma, Namaz, Roza, Zakat, Hajj.",{"ISL005"})
addMCQ("ISL005","Islamiyat","Hijri calendar ka pehla mahina?",{"Muharram","Ramzan","Rajab","Shawwal"},1,"Hazrat Umar (RA) ke daur mein shuru hua.",{"ISL004"})
addMCQ("ISL006","Islamiyat","Khulafa-e-Rashideen kitne hain?",{"4","5","3","6"},1,"Abu Bakr, Umar, Usman, Ali (RA).",{"ISL004"})
addMCQ("ISL007","Islamiyat","Ghazwa-e-Badr kis saal hijri mein hua?",{"2 Hijri","1 Hijri","3 Hijri","5 Hijri"},1,"Islam ki pehli badi jang thi.",{"ISL005"})
addMCQ("ISL008","Islamiyat","Sab se choti Surah kaunsi hai?",{"Al-Kausar","Al-Ikhlas","An-Nasr","Al-Asr"},1,"Sirf 3 ayaat par mushtamil hai.",{"ISL002"})
addMCQ("ISL009","Islamiyat","Sab se lambi Surah kaunsi hai?",{"Al-Baqarah","Aal-e-Imran","An-Nisa","Al-Maidah"},1,"Quran ki dusri Surah hai.",{"ISL001"})
addMCQ("ISL010","Islamiyat","Hazrat Muhammad (SAW) ki wiladat kahan hui?",{"Makkah","Madina","Taif","Yasrib"},1,"570 AD mein Makkah mein wiladat hui.",{})
addMCQ("ISL011","Islamiyat","Hijrat-e-Madina kis saal hui?",{"622 AD","610 AD","630 AD","632 AD"},1,"Isi saal se Islamic calendar shuru hota hai.",{"ISL005"})
addMCQ("ISL012","Islamiyat","Fatah-e-Makkah kis saal hui?",{"8 Hijri","2 Hijri","6 Hijri","10 Hijri"},1,"Makkah bagair khoon-kharabi ke fatah hua.",{"ISL007"})
addMCQ("ISL013","Islamiyat","Zakat ki nisaab shara mein kis dhaatu se moosoom hai?",{"Sona/Chandi","Zameen","Ghala","Maweshi"},1,"Zakat ka nisab sona ya chandi ki value se tay hota hai.",{"ISL004"})
addMCQ("ISL014","Islamiyat","Ramzan mein rozon ki tadaad kitni hoti hai?",{"29 ya 30","28","31","25"},1,"Chaand dekhe jaane par tadaad tay hoti hai.",{"ISL004"})
addMCQ("ISL015","Islamiyat","Hajj kis mahine mein ada kiya jata hai?",{"Zil-Hajj","Ramzan","Muharram","Shawwal"},1,"Zil-Hajj Islamic saal ka aakhri mahina hai.",{"ISL004","ISL005"})
addMCQ("ISL016","Islamiyat","Namaz din mein kitni martaba farz hai?",{"5","3","4","6"},1,"Fajr, Zuhr, Asr, Maghrib, Isha.",{"ISL004"})
addMCQ("ISL017","Islamiyat","Quran ki pehli Surah kaunsi hai?",{"Al-Fatiha","Al-Baqarah","Al-Alaq","Al-Ikhlas"},1,"Namaz mein har rakat mein parhi jati hai.",{"ISL001"})
addMCQ("ISL018","Islamiyat","Aitkaaf kis mahine mein karte hain?",{"Ramzan","Shawwal","Zil-Hajj","Muharram"},1,"Aakhri ashray mein masjid mein qayam karna.",{"ISL014"})
addMCQ("ISL019","Islamiyat","Qibla kis shehar ki taraf hai?",{"Makkah","Madina","Jerusalem","Baghdad"},1,"Khana-e-Kaaba ki taraf rukh kiya jata hai.",{"ISL010"})
addMCQ("ISL020","Islamiyat","Hazrat Umar (RA) Islam ke kitne khalifa the?",{"Doosre","Pehle","Teesre","Chauthe"},1,"Hazrat Abu Bakr (RA) ke baad khalifa bane.",{"ISL006"})

-- ---------------- General Science (20) ----------------
addMCQ("GS001","General Science","Insani jism mein kitni haddiyan?",{"206","208","210","204"},1,"Balig jism mein 206 haddiyan hoti hain.",{"GS002"})
addMCQ("GS002","General Science","Sab se bara organ kaunsa?",{"Skin","Liver","Lungs","Heart"},1,"Jild sab se bara organ hai.",{"GS001"})
addMCQ("GS003","General Science","Pani ka formula?",{"H2O","CO2","O2","H2O2"},1,"Do hydrogen aur ek oxygen atom.",{"GS004"})
addMCQ("GS004","General Science","Photosynthesis kahan hoti hai?",{"Chloroplast","Nucleus","Mitochondria","Ribosome"},1,"Chlorophyll sunlight absorb karta hai.",{"GS003"})
addMCQ("GS005","General Science","Zameen apni dhuri par kitne ghanton mein chakkar lagati hai?",{"24 ghante","12 ghante","365 din","30 din"},1,"Din-raat ka process banta hai.",{"GS006"})
addMCQ("GS006","General Science","Zameen Sooraj ka chakkar kitne dinon mein poora karti hai?",{"365 din","24 ghante","30 din","28 din"},1,"Ek saal banta hai.",{"GS005"})
addMCQ("GS007","General Science","Insani jism ka normal temperature kitna hota hai?",{"37°C","30°C","40°C","35°C"},1,"98.6°F ke barabar hai.",{})
addMCQ("GS008","General Science","Khoon ka group kitni qisam ka hota hai?",{"4","2","3","5"},1,"A, B, AB, O.",{})
addMCQ("GS009","General Science","DNA ka full form kya hai?",{"Deoxyribonucleic Acid","Deoxyribose Nucleic Acid","Dinucleic Acid","Dioxy Nucleic Acid"},1,"Genetic information carry karta hai.",{})
addMCQ("GS010","General Science","Sooraj se sab se qareeb sayyara kaunsa hai?",{"Mercury","Venus","Earth","Mars"},1,"Mercury sab se chota aur qareeb sayyara hai.",{"GS011"})
addMCQ("GS011","General Science","Nizam-e-Shamsi mein sab se bara sayyara kaunsa hai?",{"Jupiter","Saturn","Earth","Neptune"},1,"Jupiter sab se bara aur gas giant hai.",{"GS010"})
addMCQ("GS012","General Science","Insaan mein kitne chromosomes hote hain?",{"46","44","48","42"},1,"23 jorray, yani 46 chromosomes.",{"GS009"})
addMCQ("GS013","General Science","Photosynthesis ke doran kaunsi gas khaarij hoti hai?",{"Oxygen","Carbon Dioxide","Nitrogen","Hydrogen"},1,"Paudhe oxygen chorte hain.",{"GS004"})
addMCQ("GS014","General Science","Insani jism mein khoon banane wala organ kaunsa hai?",{"Bone Marrow","Liver","Kidney","Spleen"},1,"Bone marrow red aur white blood cells banata hai.",{"GS008"})
addMCQ("GS015","General Science","Newton ke kitne qawaneen-e-harkat hain?",{"3","2","4","5"},1,"Isaac Newton ne 3 laws of motion diye.",{})
addMCQ("GS016","General Science","Insan ka dil kitne chambers ka hota hai?",{"4","2","3","5"},1,"2 atria aur 2 ventricles.",{"GS001"})
addMCQ("GS017","General Science","Sab se halki gas kaunsi hai?",{"Hydrogen","Oxygen","Nitrogen","Helium"},1,"Periodic table mein sab se halka element bhi hai.",{})
addMCQ("GS018","General Science","Insaan ki aankh mein kitne rang dekhne wale cells hote hain?",{"3","2","4","5"},1,"Red, Green, Blue cones.",{"ES005"})
addMCQ("GS019","General Science","Photosynthesis ke liye kaunsi gas zaroori hai?",{"Carbon Dioxide","Oxygen","Nitrogen","Hydrogen"},1,"Paudhe CO2 lete hain aur O2 chorte hain.",{"GS013"})
addMCQ("GS020","General Science","Insaan ke jism mein sab se lambi haddi kaunsi hai?",{"Femur (Thigh bone)","Humerus","Tibia","Spine"},1,"Taang ki haddi sab se lambi hoti hai.",{"GS001"})

-- ---------------- Everyday Science (13) ----------------
addMCQ("ES001","Everyday Science","Thermometer kya naapta hai?",{"Temperature","Pressure","Speed","Weight"},1,"Haraarat naapta hai.",{"ES002"})
addMCQ("ES002","Everyday Science","Barometer kya naapta hai?",{"Atmospheric Pressure","Temperature","Humidity","Speed"},1,"Fiza ka dabao naapta hai.",{"ES001"})
addMCQ("ES003","Everyday Science","LED ka full form?",{"Light Emitting Diode","Light Energy Device","Low Energy Diode","Light Electric Device"},1,"Bijli ko roshni mein tabdeel karta hai.",{})
addMCQ("ES004","Everyday Science","Sound ki speed kis medium mein sab se tez hoti hai?",{"Solid","Liquid","Gas","Vacuum"},1,"Solid mein particles zyada qareeb hote hain.",{})
addMCQ("ES005","Everyday Science","Insaan ki aankh mein tasveer kahan banti hai?",{"Retina","Cornea","Lens","Pupil"},1,"Retina par ulta image banta hai jise dimagh seedha karta hai.",{})
addMCQ("ES006","Everyday Science","Refrigerator kaunsa principle use karta hai?",{"Cooling by evaporation","Heating","Magnetism","Gravity"},1,"Refrigerant evaporate hoke garmi absorb karta hai.",{})
addMCQ("ES007","Everyday Science","Rainbow mein kitne rang hote hain?",{"7","5","6","8"},1,"VIBGYOR - Violet se Red tak.",{})
addMCQ("ES008","Everyday Science","Microwave oven kaunsi waves use karta hai?",{"Microwaves","X-rays","Radio waves","Ultraviolet"},1,"Microwaves pani ke molecules ko harkat mein laati hain.",{})
addMCQ("ES009","Everyday Science","Battery kis energy ko electrical energy mein tabdeel karti hai?",{"Chemical energy","Mechanical energy","Solar energy","Heat energy"},1,"Chemical reactions se bijli banti hai.",{})
addMCQ("ES010","Everyday Science","WiFi kaunsi waves istemal karta hai?",{"Radio waves","Sound waves","Light waves","Gravity waves"},1,"Radio frequency signals data transfer karte hain.",{})
addMCQ("ES011","Everyday Science","Sound waves kis medium mein safar nahi kar saktin?",{"Vacuum","Solid","Liquid","Gas"},1,"Sound ko safar ke liye medium chahiye.",{"ES004"})
addMCQ("ES012","Everyday Science","X-ray kis kaam ke liye istemal hoti hai?",{"Andaruni jism dekhne","Bahar ki tasveer","Awaz record karne","Roshni banane"},1,"Haddiyon aur andaruni chotoon ko dekhne ke liye.",{})
addMCQ("ES013","Everyday Science","Solar panel kis energy ko bijli mein tabdeel karta hai?",{"Sunlight","Wind","Water","Heat"},1,"Photovoltaic cells sunlight ko bijli banate hain.",{"ES009"})

-- ---------------- English (20) ----------------
addMCQ("ENG001","English","'Beautiful' ka synonym?",{"Gorgeous","Ugly","Plain","Simple"},1,"Gorgeous bhi khubsurat ka matlab deta hai.",{"ENG002"})
addMCQ("ENG002","English","'Ancient' ka antonym?",{"Modern","Old","Historic","Traditional"},1,"Ancient=qadeem, opposite Modern.",{"ENG001"})
addMCQ("ENG003","English","Verb kya batata hai?",{"Action ya state","Person ya thing","Quality","Place"},1,"Action ya state zahir karta hai.",{})
addMCQ("ENG004","English","'Honest' ka noun form kya hai?",{"Honesty","Honestness","Honestation","Honestify"},1,"Adjective se noun 'Honesty' banta hai.",{})
addMCQ("ENG005","English","'Big' ka comparative degree?",{"Bigger","More big","Biggest","Big more"},1,"Single syllable adjectives mein -er add hota hai.",{})
addMCQ("ENG006","English","'Children' kis word ka plural hai?",{"Child","Children","Childs","Childes"},1,"Irregular plural form hai.",{})
addMCQ("ENG007","English","'She sings well' mein 'well' kaunsa part of speech hai?",{"Adverb","Adjective","Noun","Verb"},1,"Adverb verb ko modify karta hai.",{})
addMCQ("ENG008","English","Synonym of 'Happy'?",{"Joyful","Sad","Angry","Tired"},1,"Joyful aur Happy hum-mana lafz hain.",{"ENG001"})
addMCQ("ENG009","English","Antonym of 'Increase'?",{"Decrease","Raise","Grow","Expand"},1,"Decrease Increase ka opposite hai.",{"ENG002"})
addMCQ("ENG010","English","'Run' ka past tense?",{"Ran","Runned","Running","Runs"},1,"Irregular verb hai.",{})
addMCQ("ENG011","English","Article 'an' kab istemal hota hai?",{"Vowel sound se pehle","Consonant se pehle","Har jagah","Kabhi nahi"},1,"'An apple', 'an hour' jaise misaalon mein.",{})
addMCQ("ENG012","English","'Idiom' kise kehte hain?",{"Phrase jiska literal matlab na ho","Ek lafz","Grammar rule","Punctuation"},1,"Jaise 'break the ice' ka matlab shuruaat karna hota hai.",{})
addMCQ("ENG013","English","'Neither...nor' kaunsi conjunction hai?",{"Correlative","Coordinating","Subordinating","Simple"},1,"Do options mein se kisi ko bhi reject karti hai.",{})
addMCQ("ENG014","English","'Their', 'There', 'They're' kis type ke words hain?",{"Homophones","Synonyms","Antonyms","Prefixes"},1,"Awaaz same, matlab alag hote hain.",{})
addMCQ("ENG015","English","Sentence mein Subject kya hota hai?",{"Jo action karta hai","Jo action pe hota hai","Kaam ka naam","Waqt ka lafz"},1,"Subject wo hai jo verb ka kaam anjaam deta hai.",{"ENG003"})
addMCQ("ENG016","English","'Quick' ka synonym?",{"Fast","Slow","Lazy","Heavy"},1,"Fast aur Quick hum-mana hain.",{})
addMCQ("ENG017","English","'Difficult' ka antonym?",{"Easy","Hard","Tough","Complex"},1,"Easy Difficult ka opposite hai.",{})
addMCQ("ENG018","English","'Preposition' kya batata hai?",{"Relation between words","Action","Quality","Person"},1,"Jaise 'in', 'on', 'at' waqt/jagah zahir karte hain.",{"ENG003"})
addMCQ("ENG019","English","'Go' ka past participle?",{"Gone","Went","Going","Goed"},1,"Perfect tenses mein use hota hai.",{"ENG010"})
addMCQ("ENG020","English","'Simile' mein konsa lafz istemal hota hai?",{"Like ya As","And","But","Or"},1,"Jaise 'brave as a lion'.",{"ENG012"})

-- ---------------- Computer & IT (15) ----------------
addMCQ("IT001","Computer & IT","CPU full form?",{"Central Processing Unit","Computer Processing Unit","Central Program Unit","Control Processing Unit"},1,"Computer ka 'dimagh' kaha jata hai.",{"IT002"})
addMCQ("IT002","Computer & IT","RAM full form?",{"Random Access Memory","Read Access Memory","Random Active Memory","Real Access Memory"},1,"Temporary memory hai.",{"IT001"})
addMCQ("IT003","Computer & IT","Internet ka pehla version?",{"ARPANET","WWW","LAN","WAN"},1,"1969 mein US Dept of Defense ne banaya.",{})
addMCQ("IT004","Computer & IT","HTML ka full form?",{"HyperText Markup Language","High Text Markup Language","HyperText Making Language","Home Tool Markup Language"},1,"Web pages banane ki basic language hai.",{})
addMCQ("IT005","Computer & IT","URL ka full form?",{"Uniform Resource Locator","Universal Resource Link","Unique Resource Locator","United Resource Locator"},1,"Web address ko URL kehte hain.",{})
addMCQ("IT006","Computer & IT","'WWW' ka matlab kya hai?",{"World Wide Web","World Wide Website","Web Wide World","Wide World Web"},1,"Tim Berners-Lee ne isay banaya.",{"IT003"})
addMCQ("IT007","Computer & IT","1 Byte kitne bits ke barabar hota hai?",{"8","4","16","2"},1,"1 Byte = 8 Bits.",{})
addMCQ("IT008","Computer & IT","Operating System ki misaal?",{"Windows","MS Word","Google Chrome","Excel"},1,"Windows hardware aur software ke darmiyan connect karta hai.",{})
addMCQ("IT009","Computer & IT","USB ka full form?",{"Universal Serial Bus","United Serial Bus","Universal System Bus","Unified Serial Bus"},1,"Devices connect karne ka common port hai.",{})
addMCQ("IT010","Computer & IT","Antivirus software kis kaam ke liye hota hai?",{"Malware se hifazat","Internet speed badhana","File compress karna","Games khelna"},1,"Computer ko viruses/malware se bachata hai.",{})
addMCQ("IT011","Computer & IT","Wi-Fi ka full form?",{"Wireless Fidelity","Wireless Finder","Wide Fidelity","Wireless File"},1,"Bina taar internet connection deta hai.",{"ES010"})
addMCQ("IT012","Computer & IT","Cloud storage ka matlab kya hai?",{"Internet par data save karna","Local disk par save","Printer se print","Screen par dikhana"},1,"Google Drive, iCloud jaisi services.",{})
addMCQ("IT013","Computer & IT","Firewall kis kaam ke liye hota hai?",{"Network security","Faster internet","File compression","Video editing"},1,"Ghair-mustanad access ko rokta hai.",{"IT010"})
addMCQ("IT014","Computer & IT","Artificial Intelligence ka short form kya hai?",{"AI","IA","AT","IT"},1,"Machines ko insani zehanat dena.",{})
addMCQ("IT015","Computer & IT","Bluetooth kis range mein kaam karta hai?",{"Short range wireless","Long range wireless","Wired only","Satellite"},1,"Kareebi devices ko connect karta hai.",{"IT011"})

-- ---------------- Geography (20) ----------------
addMCQ("GEO001","Geography","Dunya ka sab se bara sehra?",{"Sahara Desert","Thar Desert","Gobi Desert","Kalahari Desert"},1,"Africa mein waqai hai.",{"PS009"})
addMCQ("GEO002","Geography","Dunya ka sab se lamba darya?",{"Nile River","Amazon River","Indus River","Yangtze River"},1,"Taqreeban 6650 km lamba.",{})
addMCQ("GEO003","Geography","Pakistan ka sab se lamba darya?",{"Sindhu (Indus)","Jhelum","Chenab","Ravi"},1,"Tibet se nikal kar Arabian Sea mein girta hai.",{"GEO001"})
addMCQ("GEO004","Geography","Dunya ka sab se ooncha pahaar kaunsa hai?",{"Mount Everest","K2","Nanga Parbat","Kilimanjaro"},1,"Nepal-China border par waqai hai.",{"GEO005"})
addMCQ("GEO005","Geography","Pakistan ka sab se ooncha pahaar kaunsa hai?",{"K2","Nanga Parbat","Tirich Mir","Rakaposhi"},1,"Dunya ka doosra sab se ooncha pahaar hai.",{"GEO004"})
addMCQ("GEO006","Geography","Dunya ka sab se bara samandar kaunsa hai?",{"Pacific Ocean","Atlantic Ocean","Indian Ocean","Arctic Ocean"},1,"Pacific Ocean tamam mahasagaron se bara hai.",{})
addMCQ("GEO007","Geography","Dunya ka sab se choota mahad-deen kaunsa hai?",{"Australia","Antarctica","Europe","South America"},1,"Australia sab se chota barr-e-azeem hai.",{})
addMCQ("GEO008","Geography","Kitne mahad-deen dunya mein hain?",{"7","6","5","8"},1,"Asia, Africa, North America, South America, Antarctica, Europe, Australia.",{"GEO007"})
addMCQ("GEO009","Geography","Sahara Desert kis continent mein hai?",{"Africa","Asia","Australia","South America"},1,"Africa ke shumal mein waqai hai.",{"GEO001"})
addMCQ("GEO010","Geography","Pakistan ke kitne padosi mulk hain?",{"4","3","5","6"},1,"China, India, Iran, Afghanistan.",{})
addMCQ("GEO011","Geography","Karakoram Highway kin do mulkon ko jorti hai?",{"Pakistan aur China","Pakistan aur India","Pakistan aur Iran","Pakistan aur Afghanistan"},1,"Dunya ki sab se oonchi paved road hai.",{"GEO005"})
addMCQ("GEO012","Geography","Pakistan ka sab se bara shehar kaunsa hai?",{"Karachi","Lahore","Islamabad","Faisalabad"},1,"Karachi Pakistan ka sab se bara shehar aur economic hub hai.",{})
addMCQ("GEO013","Geography","Pakistan ka darul-hukumat kaunsa shehar hai?",{"Islamabad","Karachi","Lahore","Rawalpindi"},1,"1960s mein capital Karachi se Islamabad shift hua.",{"GEO012"})
addMCQ("GEO014","Geography","Amazon Rainforest kahan waqai hai?",{"South America","Africa","Asia","Australia"},1,"Zyadatar Brazil mein phaila hua hai.",{})
addMCQ("GEO015","Geography","Great Barrier Reef kahan waqai hai?",{"Australia","Africa","Asia","Europe"},1,"Dunya ki sab se badi coral reef system hai.",{"GEO007"})
addMCQ("GEO016","Geography","Pakistan ka sab se garam ilaqa kaunsa mashhoor hai?",{"Sindh (Jacobabad area)","Murree","Skardu","Swat"},1,"Jacobabad dunya ke garam tareen ilaqon mein shumar hota hai.",{})
addMCQ("GEO017","Geography","Chenab, Jhelum, Ravi, Sutlej, Beas — ye kis kism ki nadiyan hain?",{"Punjab ke darya","Sindh ke darya","Balochistan ke darya","KPK ke darya"},1,"In 5 dariyaon ki wajah se 'Punjab' naam bana.",{"GEO003"})
addMCQ("GEO018","Geography","Siachen Glacier kahan waqai hai?",{"Kashmir region","Balochistan","Sindh","Punjab"},1,"Dunya ka sab se ooncha jangi maidan mana jata hai.",{"GEO005"})
addMCQ("GEO019","Geography","Dubai kis mulk mein hai?",{"UAE","Saudi Arabia","Qatar","Oman"},1,"United Arab Emirates ka mash-hoor shehar hai.",{})
addMCQ("GEO020","Geography","Makkah aur Madina kis mulk mein hain?",{"Saudi Arabia","UAE","Iraq","Jordan"},1,"Islam ke muqaddas shehar hain.",{"ISL019"})

-- ---------------- Constitution & Pak Affairs (13) ----------------
addMCQ("CN001","Constitution & Pak Affairs","1973 dastoor ke mutabiq sarkari mazhab?",{"Islam","Koi nahi","Secular","Multi-religious"},1,"Article 2 ke mutabiq Islam sarkari mazhab hai.",{"PS006"})
addMCQ("CN002","Constitution & Pak Affairs","Head of state kaun hota hai?",{"President","Prime Minister","Chief Justice","Speaker"},1,"Head of government PM hota hai.",{"CN001"})
addMCQ("CN003","Constitution & Pak Affairs","Senate ke members kitne saal ke liye muntakhib hote hain?",{"6 saal","5 saal","4 saal","3 saal"},1,"Senate Upper House hai.",{})
addMCQ("CN004","Constitution & Pak Affairs","National Assembly ke members kitne saal ke liye muntakhib hote hain?",{"5 saal","6 saal","4 saal","3 saal"},1,"General elections har 5 saal baad hote hain.",{"CN003"})
addMCQ("CN005","Constitution & Pak Affairs","Pakistan ka Supreme Court ka pehla Chief Justice kaun tha?",{"Justice Abdul Rashid","Justice Muhammad Munir","Justice Hamoodur Rehman","Justice Cornelius"},1,"1947 mein Justice Abdul Rashid pehle CJ bane.",{})
addMCQ("CN006","Constitution & Pak Affairs","Pakistan mein kitne provincial assemblies hain?",{"4","5","3","6"},1,"Har sooba ki apni assembly hoti hai.",{"PS010"})
addMCQ("CN007","Constitution & Pak Affairs","Pakistan ka National Flag kis saal design hua?",{"1947","1940","1956","1973"},1,"11 August 1947 ko design approve hua.",{})
addMCQ("CN008","Constitution & Pak Affairs","National Assembly ke total seats kitni hain?",{"336","272","300","350"},1,"General aur reserved seats milakar 336 hain.",{"CN004"})
addMCQ("CN009","Constitution & Pak Affairs","Pakistan ka darul-hukumat kab Islamabad banaya gaya?",{"1960s","1947","1973","1980s"},1,"Karachi se capital shift hua.",{"GEO013"})
addMCQ("CN010","Constitution & Pak Affairs","CPEC kis mulk ke saath mansooba hai?",{"China","India","Iran","Afghanistan"},1,"China-Pakistan Economic Corridor.",{"GEO011"})
addMCQ("CN011","Constitution & Pak Affairs","Pakistan ka National Anthem ki dorania kitni hai?",{"Taqreeban 80 second","30 second","2 minute","1 minute"},1,"Sab se lambi National Anthems mein shumar hota hai.",{"PS007"})
addMCQ("CN012","Constitution & Pak Affairs","Pakistan mein voting ki umar kitni hai?",{"18 saal","21 saal","16 saal","20 saal"},1,"18 saal ke baad vote ka haq milta hai.",{"CN004"})
addMCQ("CN013","Constitution & Pak Affairs","Election Commission of Pakistan kis kaam ke liye zimmedar hai?",{"Elections karwana","Tax jama karna","Adalat chalana","Sadak banana"},1,"Azad aur munsifana elections yaqeeni banata hai.",{"CN004"})

-- ---------------- World General Knowledge (20) ----------------
addMCQ("WGK001","World General Knowledge","United Nations ka qayam kis saal hua?",{"1945","1947","1950","1939"},1,"World War 2 ke baad qayam hua.",{})
addMCQ("WGK002","World General Knowledge","UN ka headquarters kahan hai?",{"New York","Geneva","Paris","London"},1,"USA mein waqai hai.",{"WGK001"})
addMCQ("WGK003","World General Knowledge","Dunya ka sab se chota mulk kaunsa hai?",{"Vatican City","Monaco","Malta","San Marino"},1,"Rome ke andar waqai hai.",{})
addMCQ("WGK004","World General Knowledge","Dunya ka sab se bara mulk (rakbe ke lihaz se)?",{"Russia","Canada","China","USA"},1,"Russia rakbe ke lihaz se sab se bara mulk hai.",{})
addMCQ("WGK005","World General Knowledge","Dunya ki sab se zyada aabadi wala mulk kaunsa hai?",{"India","China","USA","Indonesia"},1,"Recent data ke mutabiq India top par hai.",{})
addMCQ("WGK006","World General Knowledge","Great Wall of China kis mulk mein hai?",{"China","Japan","Mongolia","Korea"},1,"Dunya ke ajaibaat mein shumar hoti hai.",{})
addMCQ("WGK007","World General Knowledge","Eiffel Tower kis mulk mein hai?",{"France","Italy","Germany","Spain"},1,"Paris mein waqai hai.",{})
addMCQ("WGK008","World General Knowledge","Taj Mahal kis mulk mein hai?",{"India","Pakistan","Bangladesh","Iran"},1,"Agra shehar mein waqai hai.",{})
addMCQ("WGK009","World General Knowledge","WHO ka full form kya hai?",{"World Health Organization","World Human Organization","World Health Office","World Human Office"},1,"Sehat se muta'liq UN idara hai.",{"WGK001"})
addMCQ("WGK010","World General Knowledge","NASA kis mulk ki space agency hai?",{"USA","Russia","China","Japan"},1,"1958 mein qayam hua.",{})
addMCQ("WGK011","World General Knowledge","Statue of Liberty kahan waqai hai?",{"New York, USA","London, UK","Paris, France","Tokyo, Japan"},1,"France ne USA ko tohfe mein di.",{"WGK002"})
addMCQ("WGK012","World General Knowledge","Currency 'Yen' kis mulk ki hai?",{"Japan","China","Korea","Thailand"},1,"Japan ki official currency hai.",{})
addMCQ("WGK013","World General Knowledge","Dunya ka sab se ooncha imarat kaunsi hai?",{"Burj Khalifa","Eiffel Tower","Empire State Building","Shanghai Tower"},1,"Dubai, UAE mein waqai hai.",{})
addMCQ("WGK014","World General Knowledge","OIC ka full form kya hai?",{"Organisation of Islamic Cooperation","Organisation of Islamic Countries","Organisation of International Cooperation","Office of Islamic Council"},1,"Muslim mulkon ka idara hai.",{"WGK001"})
addMCQ("WGK015","World General Knowledge","IMF ka full form kya hai?",{"International Monetary Fund","International Money Fund","International Market Fund","Internal Monetary Fund"},1,"Financial stability ke liye kaam karta hai.",{"WGK001"})
addMCQ("WGK016","World General Knowledge","Antarctica kis lihaz se khaas hai?",{"Sab se sard continent","Sab se garam continent","Sab se choti continent","Sab se aabaad continent"},1,"Yahan koi permanent aabadi nahi.",{"GEO007"})
addMCQ("WGK017","World General Knowledge","Amazon River kahan waqai hai?",{"South America","Africa","Asia","North America"},1,"Brazil se guzarta hai.",{"GEO014"})
addMCQ("WGK018","World General Knowledge","Petra kis mulk mein waqai hai?",{"Jordan","Egypt","Syria","Lebanon"},1,"Qadeem shehar hai, patthar mein taraasha gaya.",{})
addMCQ("WGK019","World General Knowledge","Sydney Opera House kis mulk mein hai?",{"Australia","New Zealand","UK","Canada"},1,"Duniya ki mash-hoor imarat hai.",{"GEO015"})
addMCQ("WGK020","World General Knowledge","Kremlin kahan waqai hai?",{"Moscow, Russia","Beijing, China","Tokyo, Japan","Berlin, Germany"},1,"Russia ki hukoomat ka markaz hai.",{"WGK004"})

-- ---------------- Sports (14) ----------------
addMCQ("SP001","Sports","Cricket World Cup kitne khiladiyon ki team se khela jata hai?",{"11","10","12","9"},1,"Har team mein 11 khiladi hote hain.",{})
addMCQ("SP002","Sports","Pakistan ne Cricket World Cup pehli baar kab jeeta?",{"1992","1996","1999","1987"},1,"Imran Khan ki captaincy mein jeeta.",{"SP001"})
addMCQ("SP003","Sports","Olympic Games har kitne saal baad hote hain?",{"4 saal","2 saal","3 saal","5 saal"},1,"Summer aur Winter Olympics alag hote hain.",{})
addMCQ("SP004","Sports","Football match ka dorania kitna hota hai?",{"90 minute","60 minute","120 minute","45 minute"},1,"Do halves, har ek 45 minute ki.",{})
addMCQ("SP005","Sports","Hockey World Cup mein Pakistan ne kitni martaba jeeta?",{"4","3","5","2"},1,"Hockey mein Pakistan sab se kamiyab team raha hai.",{})
addMCQ("SP006","Sports","Squash mein Pakistan ka mash-hoor khiladi kaun tha?",{"Jahangir Khan","Imran Khan","Younis Khan","Jansher Khan (bhi option)"},1,"Jahangir Khan World Squash champion rahe.",{})
addMCQ("SP007","Sports","Cricket mein 'Century' ka matlab kya hai?",{"100 runs","50 runs","10 runs","6 runs"},1,"Ek batsman jab 100 runs banata hai.",{})
addMCQ("SP008","Sports","Tennis mein 'Grand Slam' mein kitne tournaments shamil hain?",{"4","3","5","2"},1,"Australian Open, French Open, Wimbledon, US Open.",{})
addMCQ("SP009","Sports","FIFA World Cup kis khel se muta'liq hai?",{"Football","Cricket","Hockey","Basketball"},1,"Har 4 saal baad hota hai.",{"SP003"})
addMCQ("SP010","Sports","Basketball match mein har team mein kitne khiladi hote hain?",{"5","6","7","11"},1,"Court par 5 khiladi hote hain.",{})
addMCQ("SP011","Sports","Pehla modern Olympics kahan hua tha?",{"Athens, Greece","Paris, France","London, UK","Rome, Italy"},1,"1896 mein Athens mein hua.",{"SP003"})
addMCQ("SP012","Sports","Pakistan ka qaumi khel kaunsa hai?",{"Hockey","Cricket","Football","Squash"},1,"Officially Hockey qaumi khel hai.",{"SP005"})
addMCQ("SP013","Sports","T20 cricket match mein har team kitne overs khelti hai?",{"20","50","10","30"},1,"Isi wajah se T20 kehlata hai.",{"SP001"})
addMCQ("SP014","Sports","Wimbledon kis khel se muta'liq hai?",{"Tennis","Football","Cricket","Golf"},1,"Grand Slam tournaments mein shamil hai.",{"SP008"})

-- ---------------- History (13) ----------------
addMCQ("HIS001","History","World War 1 kis saal shuru hui?",{"1914","1918","1939","1945"},1,"1918 mein khatam hui.",{"HIS002"})
addMCQ("HIS002","History","World War 2 kis saal shuru hui?",{"1939","1914","1945","1918"},1,"1945 mein khatam hui.",{"HIS001"})
addMCQ("HIS003","History","Muhammad bin Qasim ne Sindh kis saal fatah kiya?",{"712 AD","700 AD","750 AD","800 AD"},1,"Arab commander the jinhon ne Sindh fatah kiya.",{})
addMCQ("HIS004","History","Mughal Empire ka bani kaun tha?",{"Zahiruddin Babar","Akbar","Aurangzeb","Humayun"},1,"1526 mein Battle of Panipat jeet kar bunyad dali.",{})
addMCQ("HIS005","History","East India Company kis mulk se ta'lluq rakhti thi?",{"Britain","France","Portugal","Holland"},1,"British Raj ki bunyad isi company se pari.",{})
addMCQ("HIS006","History","Jang-e-Azadi kis saal hui?",{"1857","1947","1900","1800"},1,"Ise 1857 ki jang-e-azadi bhi kaha jata hai.",{})
addMCQ("HIS007","History","All India Muslim League ka qayam kis saal hua?",{"1906","1900","1913","1920"},1,"Dhaka mein qayam hua.",{"PS002"})
addMCQ("HIS008","History","Simon Commission kis saal Hindustan aayi?",{"1928","1930","1919","1935"},1,"Iske khilaf shadeed muzahmat hui.",{})
addMCQ("HIS009","History","Cold War kin do super powers ke darmiyan thi?",{"USA aur USSR","USA aur China","Britain aur France","China aur Russia"},1,"1947 se 1991 tak jaari rahi.",{"HIS002"})
addMCQ("HIS010","History","Berlin Wall kis saal gira?",{"1989","1991","1985","1995"},1,"Cold War ke ikhtitam ki nishani thi.",{"HIS009"})
addMCQ("HIS011","History","Renaissance ka aghaaz kis mulk se hua?",{"Italy","France","England","Germany"},1,"14th century mein Italy se shuru hua.",{})
addMCQ("HIS012","History","Alexander the Great kis mulk ka badshah tha?",{"Macedonia (Greece)","Rome","Persia","Egypt"},1,"Barre-sagheer tak fatah karta aaya.",{})
addMCQ("HIS013","History","Muslim Spain (Al-Andalus) kitne saal raha?",{"Taqreeban 700 saal","100 saal","300 saal","1000 saal"},1,"711 se 1492 tak Muslim hukoomat rahi.",{})

-- ---------------- Current Affairs (Verified via web search, Aug 2026) (16) ----------------
addMCQ("CA001","Current Affairs (Verified)","SAARC mein kitne mulk shamil hain?",{"8","7","9","6"},1,"South Asian Association for Regional Cooperation.",{})
addMCQ("CA002","Current Affairs (Verified)","G20 kis qisam ka forum hai?",{"Economic Forum","Sports Forum","Cultural Forum","Religious Forum"},1,"Dunya ki badi economies ka group hai.",{"WGK015"})
addMCQ("CA003","Current Affairs (Verified)","BRICS mein kaunse mulk shamil hain (bunyadi)?",{"Brazil, Russia, India, China, South Africa","USA, UK, France, Germany, Japan","Pakistan, India, China, Russia, Iran","Saudi, UAE, Qatar, Kuwait, Oman"},1,"Emerging economies ka group hai.",{"WGK004"})
addMCQ("CA004","Current Affairs (Verified)","Pakistan Stock Exchange ka short naam kya hai?",{"PSX","KSE","PSE","SBP"},1,"Pehle Karachi Stock Exchange (KSE) kehlata tha.",{})
addMCQ("CA005","Current Affairs (Verified)","State Bank of Pakistan ka qayam kis saal hua?",{"1948","1947","1950","1956"},1,"Pakistan ka markazi bank hai.",{"PS001"})
addMCQ("CA006","Current Affairs (Verified)","Motorway M-2 kin sheharon ko jorti hai?",{"Lahore-Islamabad","Karachi-Hyderabad","Peshawar-Islamabad","Multan-Lahore"},1,"Pakistan ki pehli badi motorway thi.",{"GEO013"})
addMCQ("CA007","Current Affairs (Verified)","Gwadar Port kis sooba mein waqai hai?",{"Balochistan","Sindh","Punjab","KPK"},1,"CPEC ka aham hissa hai.",{"CN010","PS009"})
addMCQ("CA008","Current Affairs (Verified)","Pakistan ka currency ka naam kya hai?",{"Rupee","Dinar","Riyal","Dollar"},1,"Pakistani Rupee (PKR).",{})
addMCQ("CA009","Current Affairs (Verified)","Pakistan ne Nuclear tests kis saal kiye?",{"1998","1990","2000","1985"},1,"Chagai, Balochistan mein tests hue.",{"PS009"})
addMCQ("CA010","Current Affairs (Verified)","Pakistan UN ka member kis saal bana?",{"1947","1948","1950","1945"},1,"Azadi ke foran baad member bana.",{"WGK001"})
addMCQ("CA011","Current Affairs (Verified)","Pakistan mein sab se bada dam kaunsa hai?",{"Tarbela Dam","Mangla Dam","Warsak Dam","Diamer-Bhasha Dam"},1,"Darya-e-Sindhu par waqai hai.",{"GEO003"})
addMCQ("CA012","Current Affairs (Verified)","Pakistan ka sab se bara airport kaunsa hai?",{"Jinnah International Airport, Karachi","Allama Iqbal Airport, Lahore","Islamabad Airport","Bacha Khan Airport, Peshawar"},1,"Karachi ka airport sab se masroof hai.",{"GEO012"})
addMCQ("CA013","Current Affairs (Verified)","OIC ka headquarters kahan hai?",{"Jeddah, Saudi Arabia","Cairo, Egypt","Islamabad, Pakistan","Riyadh, Saudi Arabia"},1,"Muslim mulkon ka markazi idara.",{"WGK014"})
addMCQ("CA014","Current Affairs (Verified)","Pakistan ke mojooda (2026) President kaun hain?",{"Asif Ali Zardari","Arif Alvi","Mamnoon Hussain","Shehbaz Sharif"},1,"Asif Ali Zardari 10 March 2024 ko doosri baar President bane, 14th President hain. (Web-search verified, Aug 2026)",{"CN002"})
addMCQ("CA015","Current Affairs (Verified)","Pakistan ke mojooda (2026) Prime Minister kaun hain?",{"Shehbaz Sharif","Imran Khan","Asif Ali Zardari","Nawaz Sharif"},1,"Shehbaz Sharif mojooda Prime Minister hain. (Web-search verified, Aug 2026)",{"CA014"})
addMCQ("CA016","Current Affairs (Verified)","Pakistan Army ke mojooda (2026) Chief of Army Staff kaun hain?",{"Field Marshal Asim Munir","General Qamar Javed Bajwa","General Raheel Sharif","General Ashfaq Kayani"},1,"Asim Munir Nov 2022 se COAS hain aur May 2025 mein Field Marshal ka rank mila, aur 27th amendment ke tehat Chief of Defence Forces bhi banaye gaye. (Web-search verified, Aug 2026)",{})

-- ===== LOAD EXPANSION FILES (local batches) =====
local EXPANSION_DIR="/sdcard/Jieshuo/mcq_data/"
local function loadExpansionFiles()
  pcall(function()
    local p=io.popen('ls "'..EXPANSION_DIR..'" 2>/dev/null')
    if not p then return end
    for fname in p:lines() do
      if fname:match("%.lua$") then
        local ok,data=pcall(dofile,EXPANSION_DIR..fname)
        if ok and type(data)=="table" then
          for _,item in ipairs(data) do
            table.insert(MCQ_DB,item)
            local found=false
            for _,c in ipairs(CATEGORIES) do if c==item.category then found=true end end
            if not found then table.insert(CATEGORIES,item.category) end
          end
        end
      end
    end
    p:close()
  end)
end
loadExpansionFiles()

-- ===== ONLINE SYNC =====
function syncOnlineMcqs(silent)
  if not _G.mcqSyncUrl or _G.mcqSyncUrl=="" then
    if not silent then
      ssd(AlertDialog.Builder(context).setTitle("No Sync URL Set").setMessage("Pehle SETTINGS mein jaakar apna Sync URL (Firebase ya JSON link) set karein.").setPositiveButton("OK",nil))
    end
    return
  end
  httpGet(_G.mcqSyncUrl,nil,sc(function(rc,rs)
    if rc~=200 then
      if not silent then ssd(AlertDialog.Builder(context).setTitle("Sync Failed").setMessage("Could not fetch data (HTTP "..rc..").").setPositiveButton("OK",nil)) end
      return
    end
    local ok,data=pcall(function() return cjson.decode(rs) end)
    if not ok or type(data)~="table" then
      if not silent then ssd(AlertDialog.Builder(context).setTitle("Sync Failed").setMessage("Response JSON valid nahi tha.").setPositiveButton("OK",nil)) end
      return
    end
    local added=0
    for _,item in pairs(data) do
      if type(item)=="table" and item.id and item.question and item.options and item.correct then
        local exists=false
        for _,m in ipairs(MCQ_DB) do if m.id==item.id then exists=true break end end
        if not exists then
          table.insert(MCQ_DB,item)
          added=added+1
          local found=false
          for _,c in ipairs(CATEGORIES) do if c==item.category then found=true end end
          if not found and item.category then table.insert(CATEGORIES,item.category) end
        end
      end
    end
    _G.mcqLastSync=os.date("%Y-%m-%d %H:%M")
    if not silent then
      ssd(AlertDialog.Builder(context).setTitle("Synced").setMessage(added.." naye MCQs mile. Total ab: "..#MCQ_DB.."\nLast Sync: ".._G.mcqLastSync).setPositiveButton("OK",nil))
    end
  end))
end

-- ===== HELPERS =====
function findById(id) for _,m in ipairs(MCQ_DB) do if m.id==id then return m end end return nil end
function getByCategory(cat) local l={} for _,m in ipairs(MCQ_DB) do if m.category==cat then table.insert(l,m) end end return l end
function searchMCQ(kw) local l={} kw=kw:lower() for _,m in ipairs(MCQ_DB) do if m.question:lower():find(kw,1,true) then table.insert(l,m) end end return l end

local bookmarks={}

-- ===== UI: question detail =====
function showQuestionDetail(m)
  local labels={"A","B","C","D"}
  local optionsText=""
  for i,opt in ipairs(m.options) do optionsText=optionsText..labels[i]..") "..opt.."\n" end
  local fullText=m.question.."\n\n"..optionsText.."\nCorrect Answer: "..labels[m.correct]..") "..m.options[m.correct].."\n\nExplanation: "..m.description
  local d=AlertDialog.Builder(context).setTitle(m.category.." - "..m.id).setMessage(fullText)
  d.setPositiveButton("READ ALOUD",sc(function() speakMcq(fullText) end))
  d.setNeutralButton("SHOW ALL RELATED",sc(function()
    if #m.related>0 then
      local relList={}
      for _,rid in ipairs(m.related) do
        local rm=findById(rid)
        if rm then table.insert(relList,rm) end
      end
      if #relList>0 then
        local titles={}
        for _,rm in ipairs(relList) do table.insert(titles,rm.id..": "..rm.question) end
        ssd(AlertDialog.Builder(context).setTitle("Related MCQs ("..#relList..")").setItems(titles,sc(function(dlg,which) showQuestionDetail(relList[which+1]) end)).setNegativeButton("BACK",nil))
      else
        ssd(AlertDialog.Builder(context).setTitle("No Related").setMessage("Related MCQs abhi database mein nahi hain.").setPositiveButton("OK",nil))
      end
    else
      ssd(AlertDialog.Builder(context).setTitle("No Related").setMessage("Is question ke koi related MCQ nahi hain.").setPositiveButton("OK",nil))
    end
  end))
  d.setNegativeButton("BOOKMARK",sc(function()
    bookmarks[m.id]=m
    ssd(AlertDialog.Builder(context).setTitle("Saved").setMessage("Bookmark ho gaya.").setPositiveButton("OK",nil))
  end))
  ssd(d)
  speakMcq(m.question)
end

function browseCategory(cat)
  local mcqs=getByCategory(cat)
  if #mcqs==0 then ssd(AlertDialog.Builder(context).setTitle("Empty").setMessage("Is category mein abhi koi MCQ nahi.").setPositiveButton("OK",nil)); return end
  local titles={}
  for _,m in ipairs(mcqs) do table.insert(titles,m.id..": "..m.question) end
  ssd(AlertDialog.Builder(context).setTitle(cat.." - Total: "..#mcqs.." MCQs").setItems(titles,sc(function(dlg,which) showQuestionDetail(mcqs[which+1]) end)).setNegativeButton("BACK",nil))
end

-- ===== QUIZ PLATFORM =====
local quizList,quizIndex,quizScore,quizAttempted={},1,0,0
local quizDialog,quizQuestionTxt,quizScoreTxt,quizRadioGroup,quizCheckBtn,quizNextBtn,quizFeedbackTxt

function renderQuizQuestion()
  if quizIndex>#quizList then
    speakMcq("Quiz khatam! Aapka final score: "..quizScore.." / "..quizAttempted)
    ssd(AlertDialog.Builder(context).setTitle("Quiz Result").setMessage("Quiz Complete!\n\nFinal Score: "..quizScore.." / "..quizAttempted).setPositiveButton("OK",nil))
    pcall(function() quizDialog.dismiss() end)
    return
  end
  local m=quizList[quizIndex]
  pcall(function()
    quizScoreTxt.setText("Question "..quizIndex.."/"..#quizList.."   Score: "..quizScore.."/"..quizAttempted)
    quizQuestionTxt.setText(m.question)
    quizFeedbackTxt.setText("")
    quizRadioGroup.clearCheck()
    quizRadioGroup.getChildAt(0).setText("A) "..m.options[1])
    quizRadioGroup.getChildAt(1).setText("B) "..m.options[2])
    quizRadioGroup.getChildAt(2).setText("C) "..m.options[3])
    quizRadioGroup.getChildAt(3).setText("D) "..m.options[4])
    quizCheckBtn.setEnabled(true)
    quizNextBtn.setEnabled(false)
  end)
  speakMcq(m.question)
end

function startQuiz(cat)
  quizList=getByCategory(cat)
  if #quizList==0 then ssd(AlertDialog.Builder(context).setTitle("Empty").setMessage("Is category mein MCQ maujood nahi.").setPositiveButton("OK",nil)); return end
  quizIndex=1; quizScore=0; quizAttempted=0

  local outer=LinearLayout(context); outer.setOrientation(1); outer.setPadding(20,20,20,20)
  quizScoreTxt=TextView(context); quizScoreTxt.setTextSize(14); outer.addView(quizScoreTxt)
  quizQuestionTxt=TextView(context); quizQuestionTxt.setTextSize(17); quizQuestionTxt.setPadding(0,14,0,14); outer.addView(quizQuestionTxt)

  quizRadioGroup=RadioGroup(context); quizRadioGroup.setOrientation(1)
  for i=1,4 do
    local rb=RadioButton(context); rb.setId(1000+i); quizRadioGroup.addView(rb)
  end
  outer.addView(quizRadioGroup)

  quizFeedbackTxt=TextView(context); quizFeedbackTxt.setPadding(0,10,0,10); outer.addView(quizFeedbackTxt)

  local btnRow=LinearLayout(context); btnRow.setOrientation(0)
  quizCheckBtn=Button(context); quizCheckBtn.setText("CHECK ANSWER"); quizCheckBtn.setLayoutParams(LinearLayout.LayoutParams(0,-2,1))
  quizNextBtn=Button(context); quizNextBtn.setText("NEXT"); quizNextBtn.setLayoutParams(LinearLayout.LayoutParams(0,-2,1)); quizNextBtn.setEnabled(false)
  btnRow.addView(quizCheckBtn); btnRow.addView(quizNextBtn)
  outer.addView(btnRow)

  local sv=ScrollView(context); sv.addView(outer)

  quizCheckBtn.onClick=sc(function()
    local checkedId=quizRadioGroup.getCheckedRadioButtonId()
    if checkedId==-1 then
      ssd(AlertDialog.Builder(context).setTitle("Select Option").setMessage("Pehle koi option select karein.").setPositiveButton("OK",nil))
      return
    end
    local chosen=checkedId-1000
    local m=quizList[quizIndex]
    quizAttempted=quizAttempted+1
    local labels={"A","B","C","D"}
    if chosen==m.correct then
      quizScore=quizScore+1
      quizFeedbackTxt.setText("Sahi Jawab! "..m.description)
      speakMcq("Sahi jawab! "..m.description)
    else
      quizFeedbackTxt.setText("Ghalat. Sahi hai: "..labels[m.correct]..") "..m.options[m.correct]..". "..m.description)
      speakMcq("Ghalat jawab. Sahi hai: "..labels[m.correct]..") "..m.options[m.correct]..". "..m.description)
    end
    quizScoreTxt.setText("Question "..quizIndex.."/"..#quizList.."   Score: "..quizScore.."/"..quizAttempted)
    quizCheckBtn.setEnabled(false)
    quizNextBtn.setEnabled(true)
  end)

  quizNextBtn.onClick=sc(function()
    quizIndex=quizIndex+1
    renderQuizQuestion()
  end)

  quizDialog=AlertDialog.Builder(context).setTitle("QUIZ - "..cat.." ("..#quizList.." MCQs)").setView(sv).setNegativeButton("END QUIZ",sc(function()
    speakMcq("Quiz ended. Score: "..quizScore.." / "..quizAttempted)
  end)).create()
  pcall(function() if not activity then quizDialog.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY) end; quizDialog.setCancelable(false); quizDialog.show() end)
  renderQuizQuestion()
end

function showCategoryMenu(cat)
  local cnt=#getByCategory(cat)
  ssd(AlertDialog.Builder(context).setTitle(cat.." - Total: "..cnt.." MCQs").setItems({"BROWSE ALL MCQs (Line by Line)","▶ START QUIZ"},sc(function(dlg,which)
    if which==0 then browseCategory(cat) else startQuiz(cat) end
  end)).setNegativeButton("BACK",nil))
end

function showSearch()
  local et=EditText(context); et.setHint("Type keyword...")
  local d=AlertDialog.Builder(context).setTitle("Search MCQs").setView(et)
  d.setPositiveButton("SEARCH",sc(function()
    local kw=tostring(et.getText()):gsub("^%s+",""):gsub("%s+$","")
    local results=searchMCQ(kw)
    if #results==0 then ssd(AlertDialog.Builder(context).setTitle("No Results").setMessage("Koi MCQ nahi mila.").setPositiveButton("OK",nil)); return end
    local titles={}
    for _,m in ipairs(results) do table.insert(titles,m.id..": "..m.question) end
    ssd(AlertDialog.Builder(context).setTitle("Results ("..#results..")").setItems(titles,sc(function(dlg2,w2) showQuestionDetail(results[w2+1]) end)).setNegativeButton("BACK",nil))
  end))
  d.setNegativeButton("CANCEL",nil)
  ssd(d)
end

function showBookmarks()
  local list={}
  for id,m in pairs(bookmarks) do table.insert(list,m) end
  if #list==0 then ssd(AlertDialog.Builder(context).setTitle("Empty").setMessage("Koi bookmark saved nahi.").setPositiveButton("OK",nil)); return end
  local titles={}
  for _,m in ipairs(list) do table.insert(titles,m.id..": "..m.question) end
  ssd(AlertDialog.Builder(context).setTitle("Bookmarks ("..#list..")").setItems(titles,sc(function(dlg,which) showQuestionDetail(list[which+1]) end)).setNegativeButton("BACK",nil))
end

function showSetSyncUrl()
  local et=EditText(context); et.setHint("Firebase/GitHub raw JSON URL..."); et.setText(_G.mcqSyncUrl)
  local d=AlertDialog.Builder(context).setTitle("Set Online Sync URL")
  d.setMessage("Firebase Realtime Database ka .json endpoint ya GitHub raw JSON file URL yahan daalein.")
  d.setView(et)
  d.setPositiveButton("SAVE",sc(function()
    _G.mcqSyncUrl=tostring(et.getText()):gsub("^%s+",""):gsub("%s+$","")
    ssd(AlertDialog.Builder(context).setTitle("Saved").setMessage("Sync URL save ho gaya.").setPositiveButton("OK",nil))
  end))
  d.setNegativeButton("CANCEL",nil)
  ssd(d)
end

function showSettings()
  local sl=LinearLayout(context); sl.setOrientation(1); sl.setPadding(16,16,16,16); local sv=ScrollView(context); sv.addView(sl)

  local ttsb=Button(context); ttsb.setText("SELECT TTS ENGINE"); ttsb.onClick=sc(function() showTTSEngineSelect() end); sl.addView(ttsb)

  local speedBtn=Button(context); speedBtn.setText("VOICE SPEED: "..tostring(_G.mcqSpeed).."x")
  local speeds={0.75,1.0,1.25,1.5}
  speedBtn.onClick=sc(function()
    local curIdx=1; for i,v in ipairs(speeds) do if math.abs(v-_G.mcqSpeed)<0.01 then curIdx=i end end
    _G.mcqSpeed=speeds[(curIdx%#speeds)+1]
    pcall(function() speedBtn.setText("VOICE SPEED: "..tostring(_G.mcqSpeed).."x") end)
  end)
  sl.addView(speedBtn)

  local muteBtn2=Button(context); muteBtn2.setText(_G.mcqMuted and "UNMUTE VOICE" or "MUTE VOICE")
  muteBtn2.onClick=sc(function() _G.mcqMuted=not _G.mcqMuted; pcall(function() muteBtn2.setText(_G.mcqMuted and "UNMUTE VOICE" or "MUTE VOICE") end) end)
  sl.addView(muteBtn2)

  local divider1=TextView(context); divider1.setText("--- Online Update / MCQ Websites ---"); divider1.setPadding(0,16,0,8); sl.addView(divider1)

  local syncSetBtn=Button(context); syncSetBtn.setText("SET ONLINE SYNC URL"); syncSetBtn.onClick=sc(function() showSetSyncUrl() end); sl.addView(syncSetBtn)

  local syncNowBtn=Button(context); syncNowBtn.setText("SYNC ONLINE MCQs NOW"); syncNowBtn.onClick=sc(function() syncOnlineMcqs(false) end); sl.addView(syncNowBtn)

  local lastSyncTxt=TextView(context); lastSyncTxt.setText("Last Sync: ".._G.mcqLastSync); lastSyncTxt.setPadding(0,4,0,10); sl.addView(lastSyncTxt)

  local pakMcqsBtn=Button(context); pakMcqsBtn.setText("Open PakMcqs.com (More MCQs)"); pakMcqsBtn.onClick=sc(function() openUrlInBrowser("https://pakmcqs.com/") end); sl.addView(pakMcqsBtn)

  local testPointBtn=Button(context); testPointBtn.setText("Open TestPoint.pk (Past Papers)"); testPointBtn.onClick=sc(function() openUrlInBrowser("https://testpoint.pk/") end); sl.addView(testPointBtn)

  local divider2=TextView(context); divider2.setText("--- About ---"); divider2.setPadding(0,16,0,8); sl.addView(divider2)

  local abt=Button(context); abt.setText("ABOUT THIS PLUGIN")
  abt.onClick=sc(function()
    ssd(AlertDialog.Builder(context).setTitle("ABOUT").setMessage("MY MCQ TRAINER\nDeveloped by Ali Razzaq\nJieshuo Plugin for PPSC/FPSC/Other Exam Prep\n\nTotal MCQs: "..#MCQ_DB.."\nLast Online Sync: ".._G.mcqLastSync.."\n\nAdd more MCQs by:\n1. Placing .lua batch files in /sdcard/Jieshuo/mcq_data/\n2. Setting an Online Sync URL above (Firebase/GitHub JSON)").setPositiveButton("OK",nil))
  end)
  sl.addView(abt)

  ssd(AlertDialog.Builder(context).setTitle("SETTINGS").setView(sv).setPositiveButton("DONE",nil))
end

-- ===== MAIN SCREEN =====
local ML=LinearLayout(context); ML.setOrientation(1); ML.setPadding(12,12,12,12)
local outerSV=ScrollView(context); outerSV.addView(ML)

local devTxt=TextView(context); devTxt.setText("Developed by Ali Razzaq"); devTxt.setTextSize(14); ML.addView(devTxt)
local totalTxt=TextView(context); totalTxt.setText("TOTAL MCQs AVAILABLE: "..#MCQ_DB); totalTxt.setTextSize(18); totalTxt.setPadding(0,4,0,14); ML.addView(totalTxt)

local catBtn=Button(context); catBtn.setText("BROWSE / QUIZ BY CATEGORY"); ML.addView(catBtn)
catBtn.onClick=sc(function()
  local catLabels={}
  for _,c in ipairs(CATEGORIES) do
    local cnt=#getByCategory(c)
    table.insert(catLabels,c.." ("..cnt.." MCQs)")
  end
  ssd(AlertDialog.Builder(context).setTitle("Select Category - Grand Total: "..#MCQ_DB).setItems(catLabels,sc(function(dlg,which) showCategoryMenu(CATEGORIES[which+1]) end)).setNegativeButton("BACK",nil))
end)

local searchBtn=Button(context); searchBtn.setText("SEARCH MCQs"); ML.addView(searchBtn)
searchBtn.onClick=sc(function() showSearch() end)

local bmBtn=Button(context); bmBtn.setText("MY BOOKMARKS"); ML.addView(bmBtn)
bmBtn.onClick=sc(function() showBookmarks() end)

local settingsBtn=Button(context); settingsBtn.setText("SETTINGS (Sync, Links, Voice)"); ML.addView(settingsBtn)
settingsBtn.onClick=sc(function() showSettings() end)

if _G.mcqSyncUrl and _G.mcqSyncUrl~="" then syncOnlineMcqs(true) end

ssd(AlertDialog.Builder(context).setTitle("MY MCQ version1.0").setView(outerSV).setPositiveButton("EXIT",nil))