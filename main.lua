require "import"
import "android.widget.*"
import "android.view.*"
import "android.content.*"
import "android.os.*"
import "android.text.*"
import "android.net.Uri"
import "android.app.AlertDialog"
import "android.speech.tts.TextToSpeech"
import "android.webkit.WebView"
import "android.webkit.WebViewClient"
import "android.webkit.WebChromeClient"
import "java.net.URL"
import "java.io.BufferedReader"
import "java.io.InputStreamReader"
import "java.io.FileWriter"
import "java.io.BufferedWriter"
import "java.io.File"
import "java.lang.Thread"
pcall(function() local SM=luajava.bindClass("android.os.StrictMode"); SM.setVmPolicy(luajava.newInstance("android.os.StrictMode$VmPolicy$Builder").build()) end)
math.randomseed(os.time())
local context=activity or service or this
local UNPACK=table.unpack or unpack
local handler=Handler(Looper.getMainLooper())
local cjson=require("cjson")

_G.mcqTtsEngineName=_G.mcqTtsEngineName or ""
_G.mcqSpeed=_G.mcqSpeed or 1.0
_G.mcqPitch=_G.mcqPitch or 1.0
_G.mcqMuted=_G.mcqMuted or false
_G.mcqReadOptions=_G.mcqReadOptions or false
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
    ttsEngine.setPitch(_G.mcqPitch or 1.0)
    ttsEngine.speak(tostring(text),TextToSpeech.QUEUE_FLUSH,nil,"mcq"..os.time())
  end)
end
-- builds the question text to speak, optionally including the 4
-- options when the "auto-read options" setting is on
function buildSpokenQuestion(m)
  if not _G.mcqReadOptions then return m.question end
  local labels={"A","B","C","D"}
  local t=m.question
  for i,opt in ipairs(m.options) do t=t..". "..labels[i]..") "..opt end
  return t
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

-- ===== IN-APP WEBSITE VIEWER (no need to leave the plugin) =====
-- Opens any URL inside a WebView shown in a dialog, so the page
-- loads right here instead of switching to Chrome/browser.
function showWebViewPage(url,title)
  if not url or url=="" then return end
  if not (url:match("^https?://")) then url="https://"..url end
  local outer=LinearLayout(context); outer.setOrientation(1)
  local progressTxt=TextView(context); progressTxt.setText("Loading: "..url); progressTxt.setTextSize(11); progressTxt.setPadding(10,6,10,6); outer.addView(progressTxt)
  local wv=WebView(context)
  wv.setLayoutParams(LinearLayout.LayoutParams(-1,1400))
  pcall(function()
    local st=wv.getSettings()
    st.setJavaScriptEnabled(true)
    st.setDomStorageEnabled(true)
    st.setLoadWithOverviewMode(true)
    st.setUseWideViewPort(true)
    st.setSupportZoom(true)
    st.setBuiltInZoomControls(true)
    st.setDisplayZoomControls(false)
  end)
  -- IMPORTANT: WebViewClient/WebChromeClient are plain Android
  -- classes (not interfaces), so they must be instantiated bare —
  -- passing an override table like an interface throws and was
  -- the cause of the "couldn't load, opening browser" fallback.
  -- A bare WebViewClient already keeps all links/navigation inside
  -- this WebView instead of jumping out to the phone's browser.
  pcall(function() wv.setWebViewClient(WebViewClient()) end)
  pcall(function() wv.setWebChromeClient(WebChromeClient()) end)
  outer.addView(wv)
  pcall(function() wv.loadUrl(url) end)
  ssd(AlertDialog.Builder(context).setTitle(title or url).setView(outer)
    .setPositiveButton("CLOSE",nil)
    .setNeutralButton("OPEN IN BROWSER",sc(function() openUrlInBrowser(url) end)))
end

-- ===== SAVED WEBSITES LIST (manage your own set of quick-launch sites) =====
_G.mcqSavedSites=_G.mcqSavedSites or {
  {name="PakMcqs.com",url="https://pakmcqs.com/"},
  {name="TestPoint.pk",url="https://testpoint.pk/"},
}
function showWebsitesMenu()
  local labels={}
  for _,s in ipairs(_G.mcqSavedSites) do table.insert(labels,s.name) end
  table.insert(labels,"+ ADD NEW WEBSITE")
  ssd(AlertDialog.Builder(context).setTitle("Websites (In-App)").setItems(labels,sc(function(dlg,which)
    if which==#labels-1 then
      showAddWebsiteDialog()
    else
      local s=_G.mcqSavedSites[which+1]
      showWebViewPage(s.url,s.name)
    end
  end)).setNegativeButton("BACK",nil))
end
function showAddWebsiteDialog()
  local layout=LinearLayout(context); layout.setOrientation(1); layout.setPadding(20,20,20,20)
  local nameLabel=TextView(context); nameLabel.setText("Website Name:"); layout.addView(nameLabel)
  local nameEdit=EditText(context); nameEdit.setHint("e.g. ilmkidunya.com"); layout.addView(nameEdit)
  local urlLabel=TextView(context); urlLabel.setText("Website URL:"); urlLabel.setPadding(0,10,0,0); layout.addView(urlLabel)
  local urlEdit=EditText(context); urlEdit.setHint("https://..."); layout.addView(urlEdit)
  ssd(AlertDialog.Builder(context).setTitle("Add Website").setView(layout).setPositiveButton("SAVE",sc(function()
    local name=tostring(nameEdit.getText()):gsub("^%s+",""):gsub("%s+$","")
    local url=tostring(urlEdit.getText()):gsub("^%s+",""):gsub("%s+$","")
    if url=="" then return end
    if name=="" then name=url end
    table.insert(_G.mcqSavedSites,{name=name,url=url})
    ssd(AlertDialog.Builder(context).setTitle("Saved").setMessage(name.." list mein add ho gayi.").setPositiveButton("OK",nil))
  end)).setNegativeButton("CANCEL",nil))
end

-- ===== SHARE / COPY =====
function mcqToShareText(m)
  local labels={"A","B","C","D"}
  local optionsText=""
  for i,opt in ipairs(m.options) do optionsText=optionsText..labels[i]..") "..opt.."\n" end
  return m.question.."\n\n"..optionsText.."\nCorrect Answer: "..labels[m.correct]..") "..m.options[m.correct]..
    "\n\nExplanation: "..(m.description or "").."\n\n[Category: "..m.category.."]"
end
function shareMcqText(m)
  pcall(function()
    local it=Intent(Intent.ACTION_SEND)
    it.setType("text/plain")
    it.putExtra(Intent.EXTRA_TEXT,mcqToShareText(m))
    it.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    context.startActivity(Intent.createChooser(it,"Share MCQ via"))
  end)
end
function copyMcqText(m)
  local ok=pcall(function()
    local cm=context.getSystemService(Context.CLIPBOARD_SERVICE)
    local clip=ClipData.newPlainText("MCQ",mcqToShareText(m))
    cm.setPrimaryClip(clip)
  end)
  ssd(AlertDialog.Builder(context).setTitle(ok and "Copied" or "Copy Failed").setMessage(ok and "MCQ clipboard mein copy ho gaya." or "Clipboard tak access nahi mila.").setPositiveButton("OK",nil))
end

-- ===== MCQ DATABASE =====
local MCQ_DB={}
local CATEGORIES={"Pakistan Studies","Islamiyat","General Science","Everyday Science","English","Computer & IT","Geography","Constitution & Pak Affairs","World General Knowledge","Sports","History","Current Affairs (Verified)"}

local function addMCQ(id,cat,q,opts,correct,desc,related)
  table.insert(MCQ_DB,{id=id,category=cat,question=q,options=opts,correct=correct,description=desc,related=related or {}})
end

-- ============================================================
-- ORIGINAL VERIFIED CORE DATABASE (209 MCQs)
-- ============================================================
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
addMCQ("IT001","Computer & IT","CPU full form?",{"Central Processing Unit","Computer Processing Unit","Central Program Unit","Control Processing Unit"},1,"Computer ka 'dimagh' kaha jata hai.",{"IT002"})
addMCQ("IT002","Computer & IT","RAM full form?",{"Random Access Memory","Read Access Memory","Random Active Memory","Real Access Memory"},1,"Temporary memory hai.",{"IT001"})
addMCQ("IT003","Computer & IT","Internet ka pehla version?",{"ARPANET","WWW","LAN","WAN"},1,"1969 mein US Dept of Defense ne banaya.",{})
addMCQ("IT004","Computer & IT","HTML ka full form?",{"HyperText Markup Language","High Text Markup Language","HyperText Making Language","Home Tool Markup Language"},1,"Web pages design karne ki basic language hai.",{})
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
addMCQ("CA014","Current Affairs (Verified)","Pakistan ke mojooda (2026) President kaun hain?",{"Asif Ali Zardari","Arif Alvi","Mamnoon Hussain","Shehbaz Sharif"},1,"Asif Ali Zardari 10 March 2024 ko doosri baar President bane. (Web-verified, Aug 2026)",{"CN002"})
addMCQ("CA015","Current Affairs (Verified)","Pakistan ke mojooda (2026) Prime Minister kaun hain?",{"Shehbaz Sharif","Imran Khan","Asif Ali Zardari","Nawaz Sharif"},1,"Shehbaz Sharif mojooda Prime Minister hain. (Web-verified, Aug 2026)",{"CA014"})
addMCQ("CA016","Current Affairs (Verified)","Pakistan Army ke mojooda (2026) Chief of Army Staff kaun hain?",{"Field Marshal Asim Munir","General Qamar Javed Bajwa","General Raheel Sharif","General Ashfaq Kayani"},1,"Asim Munir Nov 2022 se COAS hain, May 2025 mein Field Marshal ban gaye. (Web-verified, Aug 2026)",{})

-- ---------------- World General Knowledge (from user's 500-batch) ----------------
addMCQ("WN001","World General Knowledge","\"The Wealth of Nations\" ke musannif (author) Adam Smith ne yeh kitab kis saal شائع (publish) ki thi?",{"1776","1789","1801","1820"},1,"Adam Smith ki yeh maaroof tareen kitab modern economics ki buniyad mani jati hai.",{})
addMCQ("WN002","World General Knowledge","Bay of Pigs invasion kis saal aur kis mulk ke khilaf hui thi?",{"1961 (Cuba)","1959 (Vietnam)","1965 (Dominican Republic)","1954 (Guatemala)"},1,"Yeh CIA ki taraf se Cuba ki Fidel Castro government ko girane ki aik nakam koshish thi.",{})
addMCQ("WN003","World General Knowledge","International Court of Justice (ICJ) ka sadar muqam (headquarters) kahan waqie hai?",{"Geneva","Hague","New York","Vienna"},2,"ICJ Netherlands ke shahar The Hague mein Peace Palace mein waqie hai.",{})

-- ---------------- History (from user's 500-batch) ----------------
addMCQ("HN001","History","\"Treaty of Versailles\" kis saal sign ki gayi thi jis ne World War I ka khatma kiya?",{"1917","1918","1919","1921"},3,"Yeh muhaida 28 June 1919 ko Versailles Palace mein sign hua tha.",{})

-- ---------------- World General Knowledge (from user's 500-batch) ----------------
addMCQ("WN004","World General Knowledge","Duniya mein sab se pehla un-written (gair-mudawwin) constitution kis mulk ka hai?",{"United States","United Kingdom","New Zealand","Canada"},2,"UK ka constitution unwritten hai kyunke yeh kisi aik kitab ki shakal mein nahi balkay mukhtalif historical documents aur conventions par mabni hai.",{})

-- ---------------- Constitution & Pak Affairs (from user's 500-batch) ----------------
addMCQ("CNN001","Constitution & Pak Affairs","1973 ke Pakistani Constitution mein kis tarmeem (Amendment) ke tehat Fundamental Rights ko mazeed mazboot banaya gaya aur Emergency ke douran bhi unhein khatam nahi kiya ja sakta?",{"8th Amendment","18th Amendment","21st Amendment","26th Amendment"},2,"2010 ki 18th Amendment ke tehat Article 10A aur doosri tabdeeliyan ki gayin.",{})

-- ---------------- Pakistan Studies (from user's 500-batch) ----------------
addMCQ("PSN001","Pakistan Studies","Chaudhry Rahmat Ali ne \"Now or Never\" pamflet kis saal jari kiya tha?",{"1930","1931","1933","1940"},3,"Is pamflet mein pehli baar \"Pakistan\" ka lafz istamal kiya gaya tha (January 1933).",{})
addMCQ("PSN002","Pakistan Studies","All India Muslim League ka pehla session kis shahar mein muntaqid hua tha?",{"Dhaka","Karachi","Lahore","Aligarh"},1,"30 December 1906 ko Dhaka mein Muslim League ki buniyad rakhi gayi thi.",{})

-- ---------------- Constitution & Pak Affairs (from user's 500-batch) ----------------
addMCQ("CNN002","Constitution & Pak Affairs","Pakistan ki tareekh mein kaun sa Governor-General/President tha jis ne 1956 ka constitution pass karwaya?",{"Ghulam Muhammad","Iskander Mirza","Ayub Khan","Chaudhry Muhammad Ali"},2,"Iskander Mirza Pakistan ke pehle President thay jab 1956 ka constitution nafiz hua.",{})

-- ---------------- Pakistan Studies (from user's 500-batch) ----------------
addMCQ("PSN003","Pakistan Studies","Shimla Deputation 1906 ki qiyadat kis shakhsiyat ne ki thi?",{"Sir Syed Ahmed Khan","Aga Khan III","Quaid-e-Azam","Nawab Viqar-ul-Mulk"},2,"Sir Sultan Muhammad Shah (Aga Khan III) ne is deputation ki qiyadat ki thi jo Viceroy Lord Minto se mila tha.",{})

-- ---------------- Islamiyat (from user's 500-batch) ----------------
addMCQ("ISLN001","Islamiyat","kis Sahabi ko \"Asadullah\" (Allah ka Sher) ka laqab diya gaya tha?",{"Hazrat Abu Bakr","Hazrat Umar","Hazrat Ali","Hazrat Hamza"},4,"Hazrat Hamza bin Abdul-Muttalib ko unki bahaduri ki wajah se Asadullah kaha gaya.",{})
addMCQ("ISLN002","Islamiyat","Quran-e-Majeed mein kis Nabi ka zikr sab se ziyada martaba aya hai?",{"Hazrat Ibrahim","Hazrat Musa","Hazrat Isa","Hazrat Nooh"},2,"Hazrat Musa (A.S) ka zikr Quran mein sab se ziyada (qareeban 136 martaba) aya hai.",{})
addMCQ("ISLN003","Islamiyat","Sulah-e-Hudaibiyyah kis hijri mein tay payi thi?",{"5 Hijri","6 Hijri","7 Hijri","8 Hijri"},2,"Dzul-Qa'dah 6 Hijri ko yeh maahda Musalmanon aur Quraish-e-Makkah ke darmiyan hua tha.",{})
addMCQ("ISLN004","Islamiyat","\"Bait-ul-Rizwan\" ka waqia kis moqe par pesh aya tha?",{"Jang-e-Uhud","Sulah-e-Hudaibiyyah","Fateh-Makkah","Jang-e-Tabuk"},2,"Is bay'at mein Sahaba ne Hazrat Usman ki shahadat ki afwah par aakhri dam tak larnay ki qasam khai thi.",{})
addMCQ("ISLN005","Islamiyat","Kis Ghazwa ko \"Ghazwa-e-Ahzaab\" bhi kaha jata hai?",{"Ghazwa-e-Badr","Ghazwa-e-Khandaq","Ghazwa-e-Khaibar","Ghazwa-e-Hunain"},2,"Ahzaab ka matlab mukhtalif qabail ka lashkar hai jo Khandaq ki jang mein ikatha hue thay.",{})

-- ---------------- Computer & IT (from user's 500-batch) ----------------
addMCQ("ITN001","Computer & IT","World Wide Web (WWW) ki ijad kis ne ki thi?",{"Tim Berners-Lee","Bill Gates","Steve Jobs","Mark Zuckerberg"},1,"Tim Berners-Lee ne 1989 mein CERN mein WWW ko ijad kiya tha.",{})
addMCQ("ITN002","Computer & IT","Computer ki kis generation mein Vacuum Tubes ki jagah Transistors ne li thi?",{"1st Generation","2nd Generation","3rd Generation","4th Generation"},2,"2nd generation (1956-1965) mein transistors ka istamal shuru hua tha.",{})
addMCQ("ITN003","Computer & IT","SQL ka mukammal matlab (full form) kya hai?",{"Structured Query Language","Simple Question Language","System Quality Link","Sequential Query Logic"},1,"Yeh databases ko manage aur query karne ke liye use hoti hai.",{})
addMCQ("ITN004","Computer & IT","Internet par data transmission ke liye sab se buniyadi protocol kaun sa hai?",{"HTTP","FTP","TCP/IP","SMTP"},3,"Transmission Control Protocol / Internet Protocol internet ki backbone hai.",{})

-- ---------------- General Science (from user's 500-batch) ----------------
addMCQ("GSN001","General Science","Suraj ki roshni ko zameen tak pohnchne mein kitna waqt lagta hai?",{"4 minutes 30 seconds","8 minutes 20 seconds","12 minutes 10 seconds","15 minutes"},2,"Qareeban 500 seconds ya 8.3 minutes lagte hain.",{})
addMCQ("GSN002","General Science","Human body mein kis vitamin ki kami ki wajah se \"Scurvy\" ki bimari hoti hai?",{"Vitamin A","Vitamin B","Vitamin C","Vitamin D"},3,"Vitamin C (Ascorbic Acid) ki kami se masooron se khoon ana aur scurvy hota hai.",{})
addMCQ("GSN003","General Science","Heavy Water (Bhaari Pani) ka chemical formula kya hai?",{"H2O","D2O","H2O2","D3O"},2,"Heavy water nuclear reactors mein moderator ke taur par use hota hai.",{})
addMCQ("GSN004","General Science","Zameen ke atmosphere mein sab se ziyada miqdar mein kaun si gas payi jati hai?",{"Oxygen","Hydrogen","Nitrogen","Carbon Dioxide"},3,"Zameen ke atmosphere mein qareeban 78% Nitrogen gas hai.",{})
addMCQ("GSN005","General Science","Sound ki speed sab se ziyada kis medium mein hoti hai?",{"Air","Water","Steel (Solids)","Vacuum"},3,"Sound waves solids mein sab se tezi se travel karti hain kyunke particles qareeb hote hain.",{})

-- ---------------- World General Knowledge (from user's 500-batch) ----------------
addMCQ("WN005","World General Knowledge","\"Strait of Malacca\" duniya ke kin do ahem samundron/paani ke raston ko aapas mein milti hai?",{"Pacific Ocean aur Indian Ocean","Atlantic Ocean aur Arctic Ocean","Red Sea aur Arabian Sea","Mediterranean Sea aur Atlantic Ocean"},1,"Malacca Strait Malaysia aur Sumatra (Indonesia) ke darmiyan waqie hai jo dunya ka aik bara trade route hai.",{})
addMCQ("WN006","World General Knowledge","\"Atacama Desert\" duniya ke kis bar-e-azam (continent) mein waqie hai?",{"Africa","Asia","South America","Australia"},3,"Atacama desert Chile (South America) mein hai.",{})
addMCQ("WN007","World General Knowledge","\"Magna Carta\" kis saal sign kiya gaya tha jis ne badshah ke ikhtiyaraat ko mehdood kiya?",{"1215","1315","1415","1515"},1,"King John ne 15 June 1215 ko Runnymede mein Magna Carta par dastakhat kiye thay.",{})
addMCQ("WN008","World General Knowledge","United Nations (UN) ki Security Council ke kitne permanent members hain?",{"5","10","15","20"},1,"China, France, Russia, UK aur USA iske 5 permanent members hain.",{})
addMCQ("WN009","World General Knowledge","\"Dardanelles Strait\" kis mulk mein waqie hai aur yeh kin daryon/samundron ko milti hai?",{"Turkey (Aegean Sea aur Sea of Marmara)","Egypt (Red Sea aur Mediterranean)","Greece (Ionian Sea aur Adriatic)","Italy (Tyrrhenian Sea aur Ionian)"},1,"Yeh Black Sea aur Mediterranean ke darmiyan aik ahem maritime link hai.",{})

-- ---------------- Constitution & Pak Affairs (from user's 500-batch) ----------------
addMCQ("CNN003","Constitution & Pak Affairs","1956 ke Constitution ke tehat Pakistan ka sarkari naam kya rakha gaya tha?",{"Islamic Republic of Pakistan","Republic of Pakistan","Islamic State of Pakistan","Pakistan Islamic Federation"},1,"1956 ke ain ke tehat pehli baar Pakistan ko \"Islamic Republic\" qarar diya gaya tha.",{})

-- ---------------- Pakistan Studies (from user's 500-batch) ----------------
addMCQ("PSN004","Pakistan Studies","Quaid-e-Azam Muhammad Ali Jinnah ne \"Fourteen Points\" (14 Nukaat) kis ke jawab mein pesh kiye thay?",{"Nehru Report (1928)","Simon Commission (1927)","Cabinet Mission Plan (1946)","Cripps Mission (1942)"},1,"Quaid-e-Azam ne March 1929 mein Delhi mein Nehru Report ke radd-e-amal mein yeh nukaat pesh kiye thay.",{})
addMCQ("PSN005","Pakistan Studies","Allama Iqbal ne apna mashhoor \"Khutba-e-Allahabad\" kis saal irshad farmaya tha?",{"1929","1930","1931","1932"},2,"December 1930 mein Allahabad ke muqam par Muslim League ke salana ajlas mein yeh khutba diya gaya tha.",{})

-- ---------------- Constitution & Pak Affairs (from user's 500-batch) ----------------
addMCQ("CNN004","Constitution & Pak Affairs","Pakistan ki pehli Constituent Assembly ko kis Governor-General ne toot kiya tha?",{"Ghulam Muhammad","Iskander Mirza","Malik Ghulam","Khawaja Nazimuddin"},1,"October 1954 mein Governor-General Malik Ghulam Muhammad ne pehli assembly ko dissolve kar diya tha.",{})

-- ---------------- Pakistan Studies (from user's 500-batch) ----------------
addMCQ("PSN006","Pakistan Studies","\"Objective Resolution\" (Qarardad-e-Maqasid) kis tareeq ko pass ki gayi thi?",{"12 March 1949","14 August 1947","23 March 1940","11 September 1948"},1,"Liaquat Ali Khan ke dour-e-hukumat mein yeh qarardad pass hui thi jo baad mein har ain ka hissa bani.",{})

-- ---------------- Islamiyat (from user's 500-batch) ----------------
addMCQ("ISLN006","Islamiyat","Quran-e-Majeed ki kis Surah ko \"Aroos-ul-Quran\" (Quran ki Dulhan) kaha jata hai?",{"Surah Yaseen","Surah Ar-Rahman","Surah Al-Mulk","Surah Al-Baqarah"},2,"Surah Ar-Rahman ko uski khubsurti ki wajah se yeh laqab diya gaya hai.",{})
addMCQ("ISLN007","Islamiyat","Jang-e-Khaibar kis hijri mein lari gayi thi?",{"5 Hijri","6 Hijri","7 Hijri","8 Hijri"},3,"Moharram 7 Hijri mein Khaibar ke qilon par fatah hasil ki gayi thi.",{})
addMCQ("ISLN008","Islamiyat","Kis Sahabi ko \"Jami-ul-Quran\" (Quran ko jama karne wala) kaha jata hai?",{"Hazrat Abu Bakr Siddique","Hazrat Uthman bin Affan","Hazrat Zaid bin Thabit","Hazrat Ali"},3,"Hazrat Zaid bin Thabit ne Quran ko ek kitab ki shakal mein jama karne ki nigrani ki thi.",{})
addMCQ("ISLN009","Islamiyat","Huzaifa bin Al-Yaman ko Rasoolullah (S.A.W) ne kis raaz ka raaz-daar banaya tha?",{"Munafiqeen ke naam","Jang-e-Badr ki hikmat-e-amli","Bait-ul-Mal ki chabiyan","Fath-e-Makkah ka plan"},1,"Aap (S.A.W) ne sirf Hazrat Huzaifa ko shehar ke munafiqeen ke naam bataye thay.",{})
addMCQ("ISLN010","Islamiyat","Pehli Wahi (First Revelation) ke waqt Nabi Kareem (S.A.W) ki umar mubarak kitni thi?",{"35 saal","40 saal","43 saal","45 saal"},2,"40 saal ki umar mein Gar-e-Hira mein pehli wahi nazil hui thi.",{})

-- ---------------- Computer & IT (from user's 500-batch) ----------------
addMCQ("ITN005","Computer & IT","OSI model mein total kitni layers hoti hain?",{"5","6","7","8"},3,"OSI model mein 7 layers hoti hain.",{})
addMCQ("ITN006","Computer & IT","Computer ki memory mein \"Cache Memory\" ka asal maqsad kya hota hai?",{"Storage barhana","CPU aur RAM ke darmiyan speed ka gap kam karna","Permanent data save rakhna","Virus protect karna"},2,"Cache memory frequently used data ko CPU ke qareeb rakhti hai.",{})
addMCQ("ITN007","Computer & IT","HTML ka mukammal matlab kya hai?",{"HyperText Markup Language","Hyperlink Text Management Language","High Tech Modern Language","Hyper Transfer Markup Logic"},1,"Yeh web pages design karne ke liye use hoti hai.",{})
addMCQ("ITN008","Computer & IT","Linux kis qisam ka operating system hai?",{"Proprietary OS","Open-Source OS","Closed-Source OS","Single-User OS"},2,"Linux kernel open-source hai.",{})
addMCQ("ITN009","Computer & IT","IPV4 address ki length kitne bits ki hoti hai?",{"16 bits","32 bits","64 bits","128 bits"},2,"IPv4 addresses 32 bits ke hotay hain.",{})

-- ---------------- General Science (from user's 500-batch) ----------------
addMCQ("GSN006","General Science","Insani aankh mein image (tasweer) kahan par banti hai?",{"Cornea","Pupil","Retina","Iris"},3,"Retina par light parne se real aur inverted image banti hai.",{})
addMCQ("GSN007","General Science","\"Dry Ice\" (Khushk Baraf) asal mein kis gas ki solid form hoti hai?",{"Oxygen","Nitrogen","Carbon Dioxide","Hydrogen"},3,"Solid carbon dioxide ko dry ice kaha jata hai.",{})
addMCQ("GSN008","General Science","Penicillin ki ijad (discovery) kis ne ki thi?",{"Alexander Fleming","Louis Pasteur","Edward Jenner","Robert Koch"},1,"1928 mein Alexander Fleming ne pehla antibiotic daryaft kiya tha.",{})
addMCQ("GSN009","General Science","Zameen ki gravitational pull se nikalne ke liye kis minimum velocity ki zarurat hoti hai?",{"5 km/s","11.2 km/s","22.4 km/s","30 km/s"},2,"Is raftaar ko Escape Velocity kaha jata hai.",{})
addMCQ("GSN010","General Science","Chemical elements ki Periodic Table mein sab se halka element kaun sa hai?",{"Helium","Hydrogen","Lithium","Carbon"},2,"Hydrogen periodic table ka pehla aur sab se halka element hai.",{})

-- ---------------- World General Knowledge (from user's 500-batch) ----------------
addMCQ("WN010","World General Knowledge","\"Balfour Declaration\" kis saal jari ki gayi thi?",{"1915","1917","1919","1921"},2,"British Foreign Secretary Arthur Balfour ne 2 November 1917 ko yeh declaration jari ki thi.",{})
addMCQ("WN011","World General Knowledge","\"Dead Sea\" kin do mumalik ke darmiyan waqie hai?",{"Jordan aur Israel","Egypt aur Sudan","Saudi Arabia aur Iran","Turkey aur Syria"},1,"Dead Sea dunya ki sab se nichli jagah hai.",{})
addMCQ("WN012","World General Knowledge","\"League of Nations\" ka qiyam kis saal amal mein aaya tha?",{"1918","1919","1920","1922"},3,"January 1920 mein League of Nations banai gayi thi.",{})
addMCQ("WN013","World General Knowledge","\"Gobi Desert\" zyadatar kis mulk mein phailaa hua hai?",{"Mongolia aur China","Kazakhstan aur Uzbekistan","Australia aur Indonesia","Chile aur Argentina"},1,"Gobi aik cold desert hai jo Asia ke north mein waqie hai.",{})

-- ---------------- Constitution & Pak Affairs (from user's 500-batch) ----------------
addMCQ("CNN005","Constitution & Pak Affairs","1962 ke Constitution ke tehat Pakistan mein kis qisam ka political system nafiz kiya gaya tha?",{"Parliamentary System","Presidential System","Absolute Monarchy","Federal Democratic System"},2,"Ayub Khan ke dour mein Presidential system laya gaya tha.",{})

-- ---------------- Pakistan Studies (from user's 500-batch) ----------------
addMCQ("PSN007","Pakistan Studies","\"Chaudhry Rehmat Ali\" ne pehli baar kis booklet mein \"Now or Never\" ke zariye Pakistan ka naam tajweez kiya tha?",{"What Then Must We Do?","Now or Never: Are We to Live or Perish For Ever?","The Pakistan Declaration","Indian Muslim Plight"},2,"Yeh pamflet 28 January 1933 ko Cambridge se shaya kiya gaya tha.",{})
addMCQ("PSN008","Pakistan Studies","Pakistan ka pehla \"Industrial Policy\" kis saal announce ki gayi thi?",{"1948","1950","1952","1955"},1,"Pakistan ki pehli industrial conference 1948 mein hui thi.",{})

-- ---------------- Constitution & Pak Affairs (from user's 500-batch) ----------------
addMCQ("CNN006","Constitution & Pak Affairs","1973 ke Ain ke mutabiq Senate ke total members ki tadaad shuru mein kitni thi jo baad mein barh kar 104 ho gayi?",{"45","63","87","90"},2,"Shuru mein Senate ke 63 members thay.",{})

-- ---------------- Pakistan Studies (from user's 500-batch) ----------------
addMCQ("PSN009","Pakistan Studies","\"Rann of Kutch\" ka dispute Pakistan aur kis mulk ke darmiyan aik aham territorial issue raha hai?",{"India","Afghanistan","China","Iran"},1,"Yeh dispute Sindh aur Gujarat ke border par salt marsh area se mutaliq tha.",{})

-- ---------------- Islamiyat (from user's 500-batch) ----------------
addMCQ("ISLN011","Islamiyat","Kis Sahabi ko \"Amir-ul-Ummah\" (Ummah ka Ameer) ke laqab se nawaza gaya tha?",{"Abu Ubaidah bin al-Jarrah","Talha bin Ubaidullah","Saad bin Abi Waqas","Zubair bin al-Awwam"},1,"Rasoolullah (S.A.W) ne Abu Ubaidah ko is laqab se yaad farmaya tha.",{})
addMCQ("ISLN012","Islamiyat","Quran-e-Majeed ki kis Surah mein \"Bismillah\" do martaba aayi hai?",{"Surah Al-Baqarah","Surah An-Naml","Surah At-Tawbah","Surah Hud"},2,"Surah An-Naml ki aayat number 30 mein bhi Bismillah aati hai.",{})
addMCQ("ISLN013","Islamiyat","Hazrat Usman (R.A) ki shahadat kis hijri mein waqie hui thi?",{"30 Hijri","32 Hijri","35 Hijri","40 Hijri"},3,"35 Hijri mein Fitna ke douran aap shaheed hue thay.",{})
addMCQ("ISLN014","Islamiyat","Masjid-e-Nabawi mein pehli tableegh ya darsgah kis jagah qayam ki gayi thi jahan ashab-e-suffah rehte thay?",{"Suffah","Riyaz-ul-Jannah","Minbar ke paas","Bab-us-Salam"},1,"Ghareeb aur be-ghar sahaba Suffah mein reh kar ilm hasil karte thay.",{})
addMCQ("ISLN015","Islamiyat","Jang-e-Hunain kis ke khilaf lari gayi thi?",{"Qabila Hawazin aur Thaqif","Qabila Banu Nadir","Qabila Banu Quraiza","Roman Empire"},1,"Fateh Makkah ke foran baad 8 Hijri mein yeh jang lari gayi thi.",{})

-- ---------------- Computer & IT (from user's 500-batch) ----------------
addMCQ("ITN010","Computer & IT","\"SQL Injection\" kis qisam ka threat ya attack hai?",{"Hardware damage","Database security vulnerability attack","Network packet sniffing","Password guessing virus"},2,"Is attack ke zariye hacker malicious SQL statements execute karwata hai.",{})
addMCQ("ITN011","Computer & IT","Computer network mein \"MAC Address\" ki length kitni hoti hai?",{"32 bits","48 bits","64 bits","128 bits"},2,"MAC address aik unique physical address hota hai.",{})
addMCQ("ITN012","Computer & IT","Python programming language kis ne ijad ki thi?",{"Guido van Rossum","Dennis Ritchie","James Gosling","Bjarne Stroustrup"},1,"1991 mein Guido van Rossum ne Python ko launch kiya tha.",{})
addMCQ("ITN013","Computer & IT","Web browser mein \"Cookies\" ka asal maqsad kya hota hai?",{"Computer ko virus se bachana","User ki browsing preferences aur session data yaad rakhna","Internet speed tezz karna","Hard disk clean karna"},2,"Cookies choti files hoti hain jo website server save karta hai.",{})
addMCQ("ITN014","Computer & IT","DNS ka mukammal matlab kya hai?",{"Domain Name System","Data Network Security","Digital Naming Service","Direct Node Source"},1,"DNS domain names ko IP addresses mein translate karta hai.",{})

-- ---------------- General Science (from user's 500-batch) ----------------
addMCQ("GSN011","General Science","Insani jism mein sab se bari gland kaun si hai?",{"Pancreas","Liver","Thyroid","Pituitary"},2,"Liver insani jism ki sab se bari internal organ hai.",{})
addMCQ("GSN012","General Science","\"Bauxite\" kis metal ka sab se main ore hai?",{"Iron","Copper","Aluminium","Gold"},3,"Aluminium ko bauxite ore se alag kiya jata hai.",{})
addMCQ("GSN013","General Science","Light year kis cheez ki unit hai?",{"Time","Speed","Distance","Brightness"},3,"Light year woh fasla hai jo roshni aik saal mein tay karti hai.",{})
addMCQ("GSN014","General Science","Vitamin B12 ka chemical name kya hai?",{"Retinol","Ascorbic Acid","Cobalamin","Tocopherol"},3,"Is vitamin mein Cobalt mojood hota hai.",{})
addMCQ("GSN015","General Science","Earth ke core mein sab se ziyada konsa element paya jata hai?",{"Silicon aur Oxygen","Iron aur Nickel","Gold aur Silver","Hydrogen aur Helium"},2,"Zameen ka core zyadatar Iron aur Nickel par mushtamil hai.",{})

-- ---------------- History (from user's 500-batch) ----------------
addMCQ("HN002","History","\"Treaty of Lausanne\" kis saal sign ki gayi thi jis ne modern Turkey ki borders ko tasleem karwaya?",{"1920","1923","1925","1928"},2,"24 July 1923 ko yeh muhaida Lausanne mein sign hua tha.",{})

-- ---------------- World General Knowledge (from user's 500-batch) ----------------
addMCQ("WN014","World General Knowledge","\"Suez Canal\" ko kis saal official taur par navigation ke liye khola gaya tha?",{"1859","1869","1875","1882"},2,"November 1869 mein Mediterranean Sea ko Red Sea se milane wali yeh canal kholi gayi thi.",{})
addMCQ("WN015","World General Knowledge","International Labour Organization (ILO) ka headquarter kahan waqie hai?",{"Geneva","New York","Paris","Rome"},1,"ILO ka sadar muqam Switzerland ke Geneva mein hai.",{})

-- ---------------- History (from user's 500-batch) ----------------
addMCQ("HN003","History","\"Potsdam Conference\" kis saal muntaqid hui thi?",{"1943","1945","1947","1950"},2,"July-August 1945 mein yeh conference hui thi.",{})

-- ---------------- World General Knowledge (from user's 500-batch) ----------------
addMCQ("WN016","World General Knowledge","\"Caspian Sea\" ki coast line kis mulk ke sath nahi lagti?",{"Iran","Kazakhstan","Iraq","Azerbaijan"},3,"Caspian Sea ke ird-gird Russia, Iran, Kazakhstan, Azerbaijan aur Turkmenistan hain.",{})
addMCQ("WN017","World General Knowledge","\"Bering Strait\" kin do bare azmon ko alag karti hai?",{"Asia aur North America","Europe aur Africa","South America aur Antarctica","Asia aur Australia"},1,"Yeh strait Russia aur USA ke darmiyan hai.",{})
addMCQ("WN018","World General Knowledge","\"Red Cross\" organization ki buniyad kis ne rakhi thi?",{"Henry Dunant","Florence Nightingale","Woodrow Wilson","Jean-Jacques Rousseau"},1,"1863 mein Henry Dunant ne Red Cross ki buniyad rakhi thi.",{})
addMCQ("WN019","World General Knowledge","\"Great Barrier Reef\" kis mulk ke coast ke paas waqie hai?",{"Australia","South Africa","Indonesia","Brazil"},1,"Yeh coral reef system Australia ke Queensland ke east coast par hai.",{})
addMCQ("WN020","World General Knowledge","\"Panama Canal\" ka control 1999 mein kis mulk se Panama ko transfer kiya gaya?",{"United Kingdom","France","United States","Spain"},3,"December 1999 mein control Panama ke hawaley kiya gaya.",{})

-- ---------------- History (from user's 500-batch) ----------------
addMCQ("HN004","History","\"Nuremberg Trials\" ka taluq kis waqie ke baad ke trials se hai?",{"World War I war criminals","Nazi leaders after World War II","Cold War spies","Vietnam War crimes"},2,"Yeh trials Nuremberg mein Nazi leaders ke khilaf chalaye gaye thay.",{})

-- ---------------- Pakistan Studies (from user's 500-batch) ----------------
addMCQ("PSN010","Pakistan Studies","Pakistan mein pehli Martial Law kis tarikh ko nafiz kiya gaya tha?",{"7 October 1958","27 October 1958","24 March 1969","5 July 1977"},1,"Iskander Mirza ne 7 October 1958 ko martial law lagaya tha.",{})
addMCQ("PSN011","Pakistan Studies","\"Radcliffe Award\" kis tareeq ko announce kiya gaya tha?",{"14 August 1947","15 August 1947","17 August 1947","12 August 1947"},3,"Boundaries ka elaan 17 August 1947 ko kiya gaya tha.",{})

-- ---------------- Constitution & Pak Affairs (from user's 500-batch) ----------------
addMCQ("CNN007","Constitution & Pak Affairs","1973 ke Ain mein pehli tarmeem ke zariye Pakistan ne kis mulk ko officially recognize kiya tha?",{"Bangladesh","Israel","Taiwan","Vietnam"},1,"1974 mein pehli tarmeem ke tehat Bangladesh ko tasleem kiya gaya.",{})

-- ---------------- Pakistan Studies (from user's 500-batch) ----------------
addMCQ("PSN012","Pakistan Studies","All India Muslim League ka 1940 ka salana ajlas kis shahar mein hua tha jahan Qarardad-e-Pakistan pass hui?",{"Lahore","Karachi","Delhi","Lucknow"},1,"22-24 March 1940 ko Lahore mein yeh ajlas hua tha.",{})
addMCQ("PSN013","Pakistan Studies","Quaid-e-Azam ne kis saal State Bank of Pakistan ka irtetah kiya tha?",{"1947","1948","1949","1950"},2,"1 July 1948 ko State Bank ka irtetah kiya.",{})
addMCQ("PSN014","Pakistan Studies","\"Simla Agreement\" Pakistan aur India ke darmiyan kis saal sign hua tha?",{"1965","1971","1972","1974"},3,"2 July 1972 ko Shimla mein yeh muhaida sign hua tha.",{})

-- ---------------- Constitution & Pak Affairs (from user's 500-batch) ----------------
addMCQ("CNN008","Constitution & Pak Affairs","Pakistan ka pehla constitutional Governor-General kaun tha?",{"Quaid-e-Azam Muhammad Ali Jinnah","Khawaja Nazimuddin","Ghulam Muhammad","Iskander Mirza"},1,"Quaid-e-Azam Pakistan ke pehle Governor-General thay.",{})

-- ---------------- Pakistan Studies (from user's 500-batch) ----------------
addMCQ("PSN015","Pakistan Studies","\"Objective Resolution\" kis Pakistani Prime Minister ke dour mein pesh ki gayi thi?",{"Liaquat Ali Khan","Khawaja Nazimuddin","Muhammad Ali Bogra","Huseyn Shaheed Suhrawardy"},1,"12 March 1949 ko Liaquat Ali Khan ne ise pass karwaya tha.",{})
addMCQ("PSN016","Pakistan Studies","Liaquat-Nehru Pact kis saal sign hua tha?",{"1948","1950","1952","1954"},2,"April 1950 mein Delhi mein yeh pact sign hua tha.",{})

-- ---------------- Constitution & Pak Affairs (from user's 500-batch) ----------------
addMCQ("CNN009","Constitution & Pak Affairs","1973 ke Ain ke tehat Pakistan ka sadar banne ke liye kam az kam umar kitni honi chahiye?",{"35 saal","40 saal","45 saal","50 saal"},3,"Article 41 ke tehat President ke liye minimum age 45 years hai.",{})

-- ---------------- Islamiyat (from user's 500-batch) ----------------
addMCQ("ISLN016","Islamiyat","Kis Sahabi ko \"Zul-Noorain\" ka laqab diya gaya tha?",{"Hazrat Ali","Hazrat Usman bin Affan","Hazrat Ubaidah","Hazrat Talha"},2,"Ruqayya aur Umm Kulthum (R.A) ka nikah Hazrat Usman se hua tha.",{})
addMCQ("ISLN017","Islamiyat","Surah Al-Baqarah mein kul kitni aayaat hain?",{"200","250","286","300"},3,"Surah Al-Baqarah Quran ki sab se lambi surah hai.",{})
addMCQ("ISLN018","Islamiyat","\"Bait-ul-Maqdas\" (Jerusalem) ko kis Musalman fateh ke dour mein fatah kiya gaya tha?",{"Hazrat Abu Bakr","Hazrat Umar ibn al-Khattab","Hazrat Uthman","Khalid bin Walid"},2,"15 Hijri mein Bait-ul-Maqdas ki chabiyan li gayi thin.",{})
addMCQ("ISLN019","Islamiyat","Islami calendar ki shuruaat kis Khalifa ke dour mein hui thi?",{"Hazrat Abu Bakr","Hazrat Umar","Hazrat Uthman","Hazrat Ali"},2,"Hazrat Umar ke dour mein 17 Hijri mein Hijri calendar ko formal banaya gaya tha.",{})
addMCQ("ISLN020","Islamiyat","Kis Ghazwa mein Musalmanon ko shuru mein shikast ka samna karna para tha lekin baad mein fatah mili?",{"Ghazwa-e-Badr","Ghazwa-e-Uhud","Ghazwa-e-Hunain","Ghazwa-e-Khyber"},3,"Jang-e-Hunain mein achanak hamle ke baad fatah hui thi.",{})
addMCQ("ISLN021","Islamiyat","Quran-e-Majeed mein kitni Makki aur kitni Madani Surah hain?",{"86 Makki 28 Madani","90 Makki 24 Madani","80 Makki 34 Madani","82 Makki 32 Madani"},1,"Kul 114 surah mein se 86 Makki aur 28 Madani hain.",{})
addMCQ("ISLN022","Islamiyat","\"Sahih al-Bukhari\" ke musannif ka watan kaun sa shahar tha?",{"Bukhara","Nishapur","Baghdad","Samarkand"},1,"Bukhara mein Imam Bukhari paida hue thay.",{})
addMCQ("ISLN023","Islamiyat","Namaz-e-Janaza mein kaun sa rukan shamil nahi hota?",{"Ruku aur Sajdah","Surah Fatiha","Durood Shareef","Dua for deceased"},1,"Namaz-e-Janaza khare ho kar ada ki jati hai.",{})
addMCQ("ISLN024","Islamiyat","Kis Nabi par \"Zaboor\" kitab nazil ki gayi thi?",{"Hazrat Musa","Hazrat Dawood","Hazrat Isa","Hazrat Ibrahim"},2,"Hazrat Dawood (A.S) par Zaboor nazil ki gayi thi.",{})
addMCQ("ISLN025","Islamiyat","Jang-e-Yamamah kis ke khilaf lari gayi thi?",{"Musailma Kazzab","Roman Empire","Persians","Khawarij"},1,"12 Hijri mein Hazrat Abu Bakr ke dour mein yeh jang lari gayi thi.",{})

-- ---------------- Computer & IT (from user's 500-batch) ----------------
addMCQ("ITN015","Computer & IT","Computer ki \"First Generation\" mein kis main electronic component ka istamal hota tha?",{"Transistors","Vacuum Tubes","Integrated Circuits","Microprocessors"},2,"1940-1956 ke douran vacuum tubes ka istamal hota tha.",{})
addMCQ("ITN016","Computer & IT","HTTPS ka \"S\" kis cheez ko represent karta hai?",{"System","Secure","Simple","Standard"},2,"HTTPS data ko encrypt karta hai.",{})
addMCQ("ITN017","Computer & IT","Operating System mein \"Deadlock\" ki surat-e-hal kab paida hoti hai?",{"Jab computer hang ho jaye","Jab do processes aik doosre ke resources ka wait kar rahi hon","Jab internet disconnect ho jaye","Jab RAM full ho jaye"},2,"OS concurrency ka classic problem hai.",{})
addMCQ("ITN018","Computer & IT","Excel mein formula kis sign se shuru hota hai?",{"#","@","=","$"},3,"Har formula '=' sign se shuru hota hai.",{})
addMCQ("ITN019","Computer & IT","\"Trojan Horse\" computer ki dunya mein kya hai?",{"Ek hardware device","Ek malware jo harmless lagta hai lekin nuksaan deta hai","Ek fast network cable","Ek programming language"},2,"Andar se virus ya backdoor hota hai.",{})
addMCQ("ITN020","Computer & IT","Wi-Fi ka mukammal matlab kya hai?",{"Wireless Fidelity","Wired Finder","Wide Field","Wave Filter"},1,"Wi-Fi wireless networking ki technology hai.",{})
addMCQ("ITN021","Computer & IT","Database mein \"Primary Key\" ka kya kaam hota hai?",{"Table ki har row ko uniquely identify karna","Password save karna","Data delete karna","Backup banana"},1,"Primary key unique hoti hai.",{})
addMCQ("ITN022","Computer & IT","\"ASCII\" code mein ek character kitni memory leta hai?",{"1 bit","1 byte","2 bytes","4 bytes"},2,"Standard ASCII 7 ya 8 bits use karta hai.",{})
addMCQ("ITN023","Computer & IT","CPU ka kaun sa hissa mathematical aur logical calculations perform karta hai?",{"Control Unit","Arithmetic Logic Unit","Register","Cache"},2,"ALU sare addition, subtraction aur comparisons karta hai.",{})
addMCQ("ITN024","Computer & IT","\"Phishing\" cyber attack mein hackers kya karte hain?",{"Computer ko physical damage dete hain","Fake websites ya emails ke zariye sensitive data chori karte hain","Internet speed slow karte hain","Hard disk format karte hain"},2,"Social engineering attack ki misaal hai.",{})

-- ---------------- General Science (from user's 500-batch) ----------------
addMCQ("GSN016","General Science","Insani jism mein red blood cells kahan par produce hote hain?",{"Liver","Heart","Bone Marrow","Kidneys"},3,"RBCs bone marrow mein bantay hain, life 120 days.",{})
addMCQ("GSN017","General Science","\"Ozone Layer\" zameen ke atmosphere ki kis layer mein pai jati hai?",{"Troposphere","Stratosphere","Mesosphere","Thermosphere"},2,"Stratosphere mein ozone layer UV rays ko rokti hai.",{})
addMCQ("GSN018","General Science","Pani ka maximum density kis temperature par hoti hai?",{"0C","4C","50C","100C"},2,"4C par pani ki density sab se ziyada hoti hai.",{})
addMCQ("GSN019","General Science","Universe mein sab se ziyada abundancy kis element ki hai?",{"Oxygen","Carbon","Hydrogen","Helium"},3,"Kainaat ka 73-75% hissa Hydrogen par mushtamil hai.",{})
addMCQ("GSN020","General Science","\"Photosynthesis\" ke douran paudey kaun si gas kharij karte hain?",{"Carbon Dioxide","Nitrogen","Oxygen","Hydrogen"},3,"Pauday CO2 lete hain aur Oxygen kharij karte hain.",{})
addMCQ("GSN021","General Science","Insani jism mein total bones pedaish ke waqt kitni hoti hain jo bare ho kar 206 reh jati hain?",{"206","270","300","350"},3,"Bachay ki paidaish ke waqt qareeban 300 haddiyan hoti hain.",{})
addMCQ("GSN022","General Science","\"Dynamite\" ki ijad kis ne ki thi?",{"Thomas Edison","Alfred Nobel","Albert Einstein","Isaac Newton"},2,"1867 mein Alfred Nobel ne dynamite ijad kiya tha.",{})
addMCQ("GSN023","General Science","Sound ki frequency agar 20 Hz se kam ho toh use kya kaha jata hai?",{"Ultrasonic","Infrasonic","Audible sound","Supersonic"},2,"20,000 Hz se upar ki waves ko ultrasonic kehte hain.",{})
addMCQ("GSN024","General Science","Vitamin D ki kami ki wajah se bachon mein kaun si bimari ho jati hai?",{"Scurvy","Rickets","Beriberi","Night Blindness"},2,"Rickets ki wajah se bachon ki haddiyan kamzor ho jati hain.",{})
addMCQ("GSN025","General Science","Surya ki energy ka asal zariya kya hai?",{"Nuclear Fission","Nuclear Fusion","Chemical combustion","Gravitational compression"},2,"Suraj ke core mein nuclear fusion se energy paida hoti hai.",{})

-- ---------------- History (from user's 500-batch) ----------------
addMCQ("HN005","History","\"Treaty of Sevres\" (1920) ka taluq kis empire ki taqseem se tha?",{"Ottoman Empire","Austro-Hungarian Empire","Russian Empire","Mughal Empire"},1,"World War I ke baad Ottoman Empire ki taqseem ke liye yeh muhaida tha.",{})

-- ---------------- World General Knowledge (from user's 500-batch) ----------------
addMCQ("WN021","World General Knowledge","\"Bosphorus Strait\" kin do paani ke zariyoun ko aapas mein milti hai?",{"Black Sea aur Sea of Marmara","Red Sea aur Arabian Sea","Caspian Sea aur Black Sea","Mediterranean Sea aur Atlantic Ocean"},1,"Yeh strait Istanbul ko do hisson mein taqseem karti hai.",{})
addMCQ("WN022","World General Knowledge","\"Amnesty International\" ka headquarters kahan waqie hai?",{"London","Geneva","New York","Paris"},1,"Human rights ki hifazat ke liye kaam karne wali organization hai.",{})
addMCQ("WN023","World General Knowledge","\"Marshall Plan\" (1947) ka asal maqsad kya tha?",{"European countries ko financial aid dena","Asian countries ko weapons dena","UN ka budget barhana","Latin America mein trade routes banana"},1,"US Secretary of State George Marshall ke naam par yeh plan shuru kiya gaya.",{})
addMCQ("WN024","World General Knowledge","\"Atacama Desert\" dunya ke kis mulk mein zyadatar waqie hai?",{"Chile","Argentina","Australia","South Africa"},1,"South America ke mulk Chile mein waqie hai.",{})

-- ---------------- History (from user's 500-batch) ----------------
addMCQ("HN006","History","\"Maastricht Treaty\" kis saal sign ki gayi thi jis se European Union bana?",{"1989","1992","1995","1999"},2,"February 1992 mein Maastricht mein yeh muhaida sign hua.",{})

-- ---------------- World General Knowledge (from user's 500-batch) ----------------
addMCQ("WN025","World General Knowledge","\"Taklamakan Desert\" zyadatar kis mulk mein waqie hai?",{"China","Mongolia","Kazakhstan","Turkmenistan"},1,"Xinjiang region mein yeh sandy desert hai.",{})
addMCQ("WN026","World General Knowledge","International Court of Justice (ICJ) mein judges ki total tadaad kitni hoti hai?",{"15 judges (9 years term)","10 judges (5 years)","21 judges (7 years)","12 judges (6 years)"},1,"Har judge ki muddat 9 saal hoti hai.",{})

-- ---------------- History (from user's 500-batch) ----------------
addMCQ("HN007","History","\"Battle of Waterloo\" kis saal lari gayi thi?",{"1812","1815","1820","1830"},2,"18 June 1815 ko Belgium mein yeh jang hui thi.",{})

-- ---------------- World General Knowledge (from user's 500-batch) ----------------
addMCQ("WN027","World General Knowledge","\"Angola\" ki currency ka kya naam hai?",{"Kwanza","Peso","Dinar","Rand"},1,"Angolan Kwanza sarkari currency hai.",{})

-- ---------------- Pakistan Studies (from user's 500-batch) ----------------
addMCQ("PSN017","Pakistan Studies","Pakistan mein pehli aam intekhabat kis saal muntaqid huay thay?",{"1950","1965","1970","1973"},3,"Yahya Khan ke dour mein December 1970 mein pehle fair general elections huay.",{})

-- ---------------- Constitution & Pak Affairs (from user's 500-batch) ----------------
addMCQ("CNN010","Constitution & Pak Affairs","1973 ke Ain ke mutabiq National Assembly ki seats mein se kitni women ke liye reserved hoti hain?",{"10","20","60","70"},3,"NA mein aurton ke liye 60 seats mukhtas hain.",{})

-- ---------------- Pakistan Studies (from user's 500-batch) ----------------
addMCQ("PSN018","Pakistan Studies","\"Chaudhry Rahmat Ali\" ka mazar kahan waqie hai?",{"Lahore","Cambridge","Delhi","Dhaka"},2,"1951 mein wafat England mein hui, Cambridge mein dafn hain.",{})
addMCQ("PSN019","Pakistan Studies","Quaid-e-Azam ne Muslim League ki sadaarat se kis saal istefa diya tha?",{"1940","1943","1947","1948"},2,"1943 mein active role reduce kiya, 1947 mein Governor-General banne ke baad chhori.",{})
addMCQ("PSN020","Pakistan Studies","\"Rawalpindi Conspiracy Case\" kis saal samne aaya tha?",{"1948","1951","1954","1958"},2,"March 1951 mein military coup ki sazish ka inkashaf hua.",{})
addMCQ("PSN021","Pakistan Studies","Pakistan ka pehla scientific satellite \"Badr-1\" kis saal launch kiya gaya tha?",{"1988","1990","1992","1995"},2,"16 July 1990 ko China ke rocket ke zariye Badr-1 bheja gaya.",{})
addMCQ("PSN022","Pakistan Studies","Allama Iqbal ki \"Asrar-e-Khudi\" kis saal shaya hui thi?",{"1911","1915","1922","1924"},2,"Iqbal ki pehli farsi mathnavi 1915 mein publish hui.",{})
addMCQ("PSN023","Pakistan Studies","Pakistan ke pehle Chief Election Commissioner kaun thay?",{"F.M. Khan","Zahoorul Haq","Justice S.A. Rahman","Akhter Hussain"},1,"Khan Fazal Muqeem Khan pehle Chief Election Commissioner thay.",{})

-- ---------------- Constitution & Pak Affairs (from user's 500-batch) ----------------
addMCQ("CNN011","Constitution & Pak Affairs","1956 ke Ain ko kis saal mansookh kiya gaya tha?",{"1958","1962","1969","1971"},1,"7 October 1958 ko Martial Law ke sath khatam kar diya gaya.",{})

-- ---------------- Pakistan Studies (from user's 500-batch) ----------------
addMCQ("PSN024","Pakistan Studies","Srinagar mein Muslim Conference ka Pakistan se ilhaq ki qarardad kis saal pass hui?",{"1946","1947 (19 July)","1948","1950"},2,"19 July 1947 ko tareekhi qarardad pass ki gayi.",{})

-- ---------------- Islamiyat (from user's 500-batch) ----------------
addMCQ("ISLN026","Islamiyat","Kis Sahabi ko \"Tarjuman-ul-Quran\" kaha jata hai?",{"Hazrat Abdullah bin Abbas","Hazrat Abu Hurairah","Hazrat Anas bin Malik","Hazrat Jabir"},1,"Nabi ki dua ki wajah se yeh laqab mila.",{})
addMCQ("ISLN027","Islamiyat","Surah Al-Maidah mein kis ahem waqie ka zikr sab se tafseel se hai?",{"Wuzu Ghusl aur Tayammum ke ahkaam","Hajj ke rules","Inheritance","Nikah aur Talaq"},1,"Surah Maidah mein Aayat-e-Wuzu shamil hai.",{})
addMCQ("ISLN028","Islamiyat","Islam mein pehli shahid aurat ka kya naam hai?",{"Hazrat Summayyah bint Khayyat","Hazrat Khadija","Hazrat Fatimah bint Asad","Hazrat Nusaybah"},1,"Islam ki pehli shaheed khawateen mein se thin.",{})
addMCQ("ISLN029","Islamiyat","Ghazwa-e-Tabuk kis hijri mein lari gayi thi?",{"8 Hijri","9 Hijri (Roman Empire)","7 Hijri","6 Hijri"},2,"Jang nahi hui thi kyunke dushman pehle hi peechhe hat gaya tha.",{})
addMCQ("ISLN030","Islamiyat","\"Sahih Muslim\" ke musannif Imam Muslim ka taluq kis shahar se tha?",{"Nishapur","Bukhara","Merv","Samarkand"},1,"Imam Muslim bin al-Hajjaj ka taluq Nishapur se tha.",{})
addMCQ("ISLN031","Islamiyat","Qibla ki tabdeeli ka hukum kis hijri mein nazil hua tha?",{"1 Hijri","2 Hijri (Masjid-e-Qiblatain)","3 Hijri","Rajab 2 Hijri"},2,"Sha'ban 2 Hijri ko Qibla tabdeel hua.",{})
addMCQ("ISLN032","Islamiyat","Quran-e-Majeed mein kitni Manzil hain?",{"5","7","10","30"},2,"7 Manzil mein taqseem kiya gaya hai.",{})
addMCQ("ISLN033","Islamiyat","Jang-e-Uhud mein Nabi Kareem (S.A.W) ka daant kis ke hamle se shaheed hua tha?",{"Utbah bin Abi Waqas","Abu Sufiyan","Khalid bin Walid","Amr bin Al-Aas"},1,"Uhud ki jang mein Aap ka chehra mubarak zakhmi hua tha.",{})
addMCQ("ISLN034","Islamiyat","Khulafa-e-Rashideen mein se kis Khalifa ka dour sab se chota tha?",{"Hazrat Abu Bakr Siddique","Hazrat Umar Farooq","Hazrat Uthman Ghani","Hazrat Ali Murtaza"},1,"Aapka dour qareeban 2 saal 3 maheenay tha.",{})
addMCQ("ISLN035","Islamiyat","Namaz-e-Istisqa kis maqsad ke liye ada ki jati hai?",{"Baarish ke liye","Solar eclipse ke liye","Khof ke waqt","Shukrana ke taur par"},1,"Khushsali ke moqe par yeh namaz padhi jati hai.",{})

-- ---------------- Computer & IT (from user's 500-batch) ----------------
addMCQ("ITN025","Computer & IT","\"BIOS\" ka mukammal matlab kya hai?",{"Basic Input Output System","Binary Integrated Operating System","Built-in Internet Online Service","Basic Internal Operation Software"},1,"BIOS motherboard par ROM chip mein hota hai.",{})
addMCQ("ITN026","Computer & IT","Computer ki \"Third Generation\" mein kis cheez ne li thi?",{"Integrated Circuits","Microprocessors","Vacuum Diodes","Artificial Neurons"},1,"3rd generation mein ICs ka istamal shuru hua.",{})
addMCQ("ITN027","Computer & IT","DNS aam taur par kis port par kaam karta hai?",{"Port 53","Port 80","Port 443","Port 21"},1,"DNS UDP/TCP port 53 par kaam karta hai.",{})
addMCQ("ITN028","Computer & IT","Phishing se bachne ke liye kis security layer ka istemal hota hai?",{"Two-Factor Authentication","Firewall","Antivirus","MAC filtering"},1,"2FA security ko mazboot banata hai.",{})
addMCQ("ITN029","Computer & IT","Excel mein #DIV/0! error ka kya matlab hota hai?",{"Number zero se divide ho raha hai","Formula galat hai","Column chota hai","Data missing hai"},1,"Value ko 0 se divide karne par yeh error aata hai.",{})
addMCQ("ITN030","Computer & IT","\"Bluetooth\" ka naam kis historical figure ke naam par rakha gaya tha?",{"King Harald Bluetooth of Denmark","Sir Isaac Newton","Blaise Pascal","Charles Babbage"},1,"10th century Viking king ke naam par.",{})
addMCQ("ITN031","Computer & IT","Linux ka mascot kaun sa janwar hai?",{"Penguin (Tux)","Dolphin","Cheetah","Owl"},1,"Linux ka official mascot Tux hai.",{})
addMCQ("ITN032","Computer & IT","\"RAM\" kis qisam ki memory hai?",{"Non-volatile aur Permanent","Volatile aur Temporary","Secondary storage","Read-only memory"},2,"Computer band hone par RAM ka data khatam ho jata hai.",{})
addMCQ("ITN033","Computer & IT","\"URL\" ka mukammal matlab kya hai?",{"Uniform Resource Locator","Universal Read Link","United Registry Language","User Route Logic"},1,"Web par kisi resource ka address hota hai.",{})
addMCQ("ITN034","Computer & IT","Computer networks mein \"Router\" ka main kaam kya hota hai?",{"Data packets ko route karna","Screen clean karna","Virus scan karna","Electricity stabilize karna"},1,"Router alag networks ko connect karta hai.",{})

-- ---------------- General Science (from user's 500-batch) ----------------
addMCQ("GSN026","General Science","Insani jism mein \"Bile\" kahan produce hota hai aur kahan store hota hai?",{"Produce Liver store Gallbladder","Produce Pancreas store Liver","Produce Kidneys store Bladder","Produce Stomach store Intestine"},1,"Bile fats ko digest karne mein madad deta hai.",{})
addMCQ("GSN027","General Science","\"Heavy Water\" ka chemical naam kya hai?",{"Deuterium Oxide","Hydrogen Peroxide","Dihydrogen Monoxide","Hydrochloric Acid"},1,"Nuclear reactors mein neutron moderator ke taur par use hota hai.",{})
addMCQ("GSN028","General Science","Light ki speed vacuum mein kitni hoti hai?",{"3x10^8 m/s","3x10^6 m/s","3x10^5 km/h","300 m/s"},1,"Roshni ki raftaar sab se tez mani jati hai.",{})
addMCQ("GSN029","General Science","\"Barometer\" kis cheez ko maapne ke liye istemal hota hai?",{"Atmospheric Pressure","Wind Speed","Humidity","Rainfall"},1,"Barometer se hawa ka dabao maapa jata hai.",{})
addMCQ("GSN030","General Science","Insani khoon ka pH level aam taur par kitna hota hai?",{"7.35 se 7.45","5.0 se 5.5","8.5 se 9.0","6.0 se 6.5"},1,"Insani blood slight alkaline hota hai.",{})
addMCQ("GSN031","General Science","\"Concave Lens\" ko aur kis naam se jana jata hai?",{"Diverging Lens","Converging Lens","Magnifying Lens","Flat Lens"},1,"Concave lens light rays ko phailata hai.",{})
addMCQ("GSN032","General Science","Zameen ke sab se qareeb kaun sa planet waqie hai?",{"Venus","Mars","Mercury","Jupiter"},1,"Venus zameen ke sab se qareeb tareen planet hai.",{})
addMCQ("GSN033","General Science","\"Vitamin C\" ka chemical naam kya hai?",{"Ascorbic Acid","Retinol","Thiamine","Tocopherol"},1,"Kami se scurvy hota hai.",{})
addMCQ("GSN034","General Science","Insani jism mein sab se choti haddi kahan hoti hai?",{"Ear (Stapes)","Nose","Finger","Toe"},1,"Kaan ke andar Stapes jism ki sab se choti bone hai.",{})
addMCQ("GSN035","General Science","\"Celsius\" aur \"Fahrenheit\" scale kis temperature par barabar hote hain?",{"-40 degrees","0 degrees","32 degrees","100 degrees"},1,"-40C aur -40F same value dete hain.",{})

-- ---------------- History (from user's 500-batch) ----------------
addMCQ("HN008","History","\"Treaty of Guadalupe Hidalgo\" (1848) ke nateje mein kis mulk ne apne ilaqe United States ko diye thay?",{"Mexico","Spain","France","Canada"},1,"Mexican-American War ke khatme par yeh muhaida sign hua.",{})

-- ---------------- World General Knowledge (from user's 500-batch) ----------------
addMCQ("WN028","World General Knowledge","\"Strait of Hormuz\" kin do paani ke zariyoun ko aapas mein milti hai?",{"Persian Gulf aur Gulf of Oman","Red Sea aur Arabian Sea","Mediterranean Sea aur Atlantic Ocean","Caspian Sea aur Black Sea"},1,"Tel ki naql-o-hamal ke liye ahem chokepoint hai.",{})
addMCQ("WN029","World General Knowledge","\"Transparency International\" ka headquarters kahan waqie hai?",{"Berlin","Geneva","Vienna","Paris"},1,"Corruption ke khilaf kaam karti hai.",{})
addMCQ("WN030","World General Knowledge","\"Camp David Accords\" (1978) kin do mumalik ke darmiyan tha?",{"Egypt aur Israel","US aur Soviet Union","India aur Pakistan","Iran aur Iraq"},1,"Jimmy Carter ki mediatorship mein yeh muhaida hua.",{})
addMCQ("WN031","World General Knowledge","\"Great Victoria Desert\" kis continent mein waqie hai?",{"Australia","Africa","South America","Asia"},1,"Australia ka sab se bara desert hai.",{})

-- ---------------- History (from user's 500-batch) ----------------
addMCQ("HN009","History","\"Maastricht Treaty\" ke zariye kaunsa block bana?",{"European Union","ASEAN","African Union","BRICS"},1,"Communities official tor par EU bani.",{})

-- ---------------- World General Knowledge (from user's 500-batch) ----------------
addMCQ("WN032","World General Knowledge","\"Siberia\" zyadatar kis mulk ki hudood mein shamil hai?",{"Russia","Canada","Kazakhstan","China"},1,"Siberia thanda mosam aur forests ke liye jana jata hai.",{})
addMCQ("WN033","World General Knowledge","UNESCO ka headquarter kahan waqie hai?",{"Paris","New York","London","Rome"},1,"Taleem science aur culture ke liye kaam karti hai.",{})

-- ---------------- History (from user's 500-batch) ----------------
addMCQ("HN010","History","\"Battle of Trafalgar\" (1805) kis ke darmiyan lari gayi thi?",{"British Royal Navy aur Franco-Spanish Navy","Napoleon aur Russia","Romans aur Carthaginians","Ottomans aur Greeks"},1,"Admiral Horatio Nelson ne fleet ki qiyadat ki.",{})

-- ---------------- World General Knowledge (from user's 500-batch) ----------------
addMCQ("WN034","World General Knowledge","\"Bolivia\" ki administrative capital ka kya naam hai?",{"La Paz","Sucre","Bogota","Quito"},1,"Sucre constitutional capital hai.",{})

-- ---------------- Constitution & Pak Affairs (from user's 500-batch) ----------------
addMCQ("CNN012","Constitution & Pak Affairs","Pakistan ki pehli Constituent Assembly ke pehle Speaker kaun muntakhab huay thay?",{"Quaid-e-Azam","Liaquat Ali Khan","Maulvi Tamizuddin Khan","Jogendra Nath Mandal"},1,"10 August 1947 ko Quaid-e-Azam pehla president banaya gaya.",{})
addMCQ("CNN013","Constitution & Pak Affairs","1973 ke Ain ke tehat PM banne ke liye kitni majority chahiye?",{"Simple majority","Two-thirds majority","Three-fourths majority","Unanimous vote"},1,"NA mein simple majority darkar hoti hai.",{})

-- ---------------- Pakistan Studies (from user's 500-batch) ----------------
addMCQ("PSN025","Pakistan Studies","Chaudhry Rahmat Ali ne \"Now or Never\" kis university mein padhte hue jari kiya?",{"University of Cambridge","University of Oxford","LSE","University of Edinburgh"},1,"Aap Cambridge University mein student thay.",{})

-- ---------------- Constitution & Pak Affairs (from user's 500-batch) ----------------
addMCQ("CNN014","Constitution & Pak Affairs","Pakistan mein CCI ka chairperson kaun hota hai?",{"Prime Minister","President","Chief Justice","Minister of Inter-Provincial Coordination"},1,"Article 153 ke tehat CCI ka head PM hota hai.",{})

-- ---------------- Pakistan Studies (from user's 500-batch) ----------------
addMCQ("PSN026","Pakistan Studies","Pakistan mein National Security Council ka formal proposal kis dour mein aaya?",{"Musharraf era 2004","1973 ain","1962 ain","1956 ain"},1,"NSC ki formation par kafi baat hui.",{})
addMCQ("PSN027","Pakistan Studies","\"Malakand Accord\" ya Nizam-e-Adl Regulation kis saal nafiz hui?",{"2009","2002","2012","2015"},1,"Malakand division mein Nizam-e-Adl ke nifaz ke liye.",{})
addMCQ("PSN028","Pakistan Studies","Allama Iqbal ki aakhri kitab kaun si thi jo unki wafat ke baad shaya hui?",{"Armaghan-e-Hijaz","Payam-e-Mashriq","Zaboor-e-Ajam","Javid Nama"},1,"1938 mein publish hui.",{})
addMCQ("PSN029","Pakistan Studies","Pakistan ke pehle Air Commander-in-Chief kaun thay?",{"Air Vice Marshal Allan Perry-Keene","Air Marshal Asghar Khan","Air Marshal Nur Khan","Air Marshal Zafar Chaudhry"},1,"British officer PAF ke pehle chief thay.",{})

-- ---------------- Constitution & Pak Affairs (from user's 500-batch) ----------------
addMCQ("CNN015","Constitution & Pak Affairs","1962 ke Constitution mein kitne articles thay?",{"250 Articles 3 Schedules","225 Articles 5 Schedules","280 Articles 7 Schedules","199 Articles 2 Schedules"},1,"Ayub Khan ke ain mein 250 articles thay.",{})
addMCQ("CNN016","Constitution & Pak Affairs","\"Chilghoza Forest\" Pakistan mein sab se ziyada kahan paye jatay hain?",{"Waziristan aur Zhob","Northern Areas","Murree Hills","Tharparkar"},1,"Sulaiman Range mein janglaat paye jatay hain.",{})

-- ---------------- Islamiyat (from user's 500-batch) ----------------
addMCQ("ISLN036","Islamiyat","Kis Sahabi ko \"Ja'far al-Tayyar\" ka laqab diya gaya?",{"Hazrat Ja'far bin Abi Talib","Hazrat Hamza","Hazrat Ali","Hazrat Ubaidah"},1,"Jang-e-Mu'tah mein dono baazu qata hone ke baad.",{})
addMCQ("ISLN037","Islamiyat","Quran-e-Majeed ki kis Surah mein \"Bani Israel\" ka zikr hai?",{"Surah Al-Isra","Surah Al-Baqarah","Surah Al-Maidah","Surah Al-Anfal"},1,"Surah No. 17 mein zikr hai.",{})
addMCQ("ISLN038","Islamiyat","Jang-e-Badr mein Musalmanon ki kul tadaad kitni thi?",{"Qareeb 313","700","1000","500"},1,"313 Sahaba is jang mein shamil thay.",{})
addMCQ("ISLN039","Islamiyat","Khandaq khodne ka mashwara kis sahabi ne diya tha?",{"Hazrat Salman Farsi","Hazrat Umar Farooq","Hazrat Ali","Hazrat Abu Bakr"},1,"Iran ki jangi hikmat-e-amli ke tehat khandaq khodi gayi.",{})
addMCQ("ISLN040","Islamiyat","Sahih al-Bukhari mein kul kitni aahadees shamil hain?",{"Qareeb 7275","3000 fixed","10000+","1500"},1,"Imam Bukhari ne inhein saheeh tareen qarar diya.",{})
addMCQ("ISLN041","Islamiyat","Quba Masjid kis hijri mein tameer ki gayi?",{"1 Hijri","2 Hijri","3 Hijri","5 Hijri"},1,"Hijrat ke foran baad Quba mein masjid banayi gayi.",{})
addMCQ("ISLN042","Islamiyat","Quran-e-Majeed mein kitni aayat-e-sajda hain?",{"14","10","7","20"},1,"Quran mein 14 muqamat par aayat-e-sajda hain.",{})
addMCQ("ISLN043","Islamiyat","Hazrat Abu Bakr Siddique ki khilafat ka duration kitna tha?",{"2 saal 3 maheenay","10 saal","6 saal","4 saal"},1,"11 Hijri se 13 Hijri tak.",{})
addMCQ("ISLN044","Islamiyat","Kis Nabi par \"Injeel\" nazil ki gayi thi?",{"Hazrat Isa","Hazrat Musa","Hazrat Dawood","Hazrat Ibrahim"},1,"Hazrat Isa par Injeel nazil ki gayi.",{})
addMCQ("ISLN045","Islamiyat","Namaz-e-Kusoof kis moqe par padhi jati hai?",{"Surya Grahan","Chand Grahan","Baarish ke liye","Khof ke waqt"},1,"Suraj grahan ke waqt yeh namaz ada ki jati hai.",{})

-- ---------------- Computer & IT (from user's 500-batch) ----------------
addMCQ("ITN035","Computer & IT","\"HTTP\" protocol kis default port par kaam karta hai?",{"Port 80","Port 443","Port 21","Port 53"},1,"HTTPS ke liye port 443 hota hai.",{})
addMCQ("ITN036","Computer & IT","Computer ki \"Fourth Generation\" mein kis technology ka istamal shuru hua?",{"Microprocessor","Transistors","Vacuum Tubes","Quantum Chips"},1,"1971 ke baad personal computers aam hue.",{})
addMCQ("ITN037","Computer & IT","Database mein \"Foreign Key\" ka main maqsad kya hai?",{"Do tables ke darmiyan relation banana","Primary row banana","Password encrypt karna","Duplicate data save karna"},1,"Doosri table ki primary key ko refer karti hai.",{})
addMCQ("ITN038","Computer & IT","\"Ransomware\" kis qisam ka malware hai?",{"Data lock/encrypt karke ransom maangta hai","Internet speed slow karta hai","Screen par ads dikhata hai","Printer kharab karta hai"},1,"Bohot khatarnak cyber attack type hai.",{})
addMCQ("ITN039","Computer & IT","Excel mein COUNTA() function ka kya kaam hota hai?",{"Non-empty cells count karna","Sirf numbers count karna","Khali cells count karna","Maximum value nikalna"},1,"Text aur numbers dono ko count karta hai.",{})
addMCQ("ITN040","Computer & IT","\"IPv6\" address ki length kitni hoti hai?",{"128 bits","32 bits","64 bits","256 bits"},1,"Hexadecimal format mein likhe jate hain.",{})
addMCQ("ITN041","Computer & IT","Linux mein file permissions check karne ke liye kaun sa command use hota hai?",{"chmod","chown","grep","ps"},1,"Change Mode se permissions set hoti hain.",{})
addMCQ("ITN042","Computer & IT","\"Cache memory\" computer mein kahan located hoti hai?",{"CPU ke andar ya qareeb","Hard disk ke andar","Power supply unit ke sath","Monitor screen mein"},1,"CPU aur RAM ke darmiyan speed gap khatam karti hai.",{})
addMCQ("ITN043","Computer & IT","HTTPS mein http ka mukammal matlab kya hai?",{"HyperText Transfer Protocol","Hyperlink Transmission Program","High Technology Transfer Protocol","Hyper Terminal Text Process"},1,"Web servers aur clients ke darmiyan data transfer.",{})
addMCQ("ITN044","Computer & IT","Switch aur Hub mein buniyadi farq kya hai?",{"Switch intelligent hota hai targeted","Hub tez hota hai","Switch sirf wireless hota hai","Koi farq nahi"},1,"Switch MAC addresses ki base par targeted communication karta hai.",{})

-- ---------------- General Science (from user's 500-batch) ----------------
addMCQ("GSN036","General Science","Insani jism mein \"Insulin\" kahan produce hota hai?",{"Pancreas","Liver","Kidneys","Thyroid"},1,"Beta cells insulin produce karte hain.",{})
addMCQ("GSN037","General Science","\"Heavy water\" nuclear reactors mein kis taur par kaam karti hai?",{"Neutron Moderator","Fuel","Coolant","Radiation shield"},1,"Neutrons ki speed slow karti hai.",{})
addMCQ("GSN038","General Science","Light frequency aur wavelength mein kya relation hota hai?",{"Inverse relation","Direct relation","Koi taluq nahi","Hamesha equal"},1,"Speed = Frequency x Wavelength.",{})
addMCQ("GSN039","General Science","\"Anemometer\" kis cheez ko maapne ke liye istemal hota hai?",{"Wind Speed","Water pressure","Sound intensity","Earthquakes"},1,"Hawa ki raftar maapi jati hai.",{})
addMCQ("GSN040","General Science","Insani khoon mein plasma ka percentage kitna hota hai?",{"Qareeb 55%","Qareeb 20%","Qareeb 80%","Qareeb 40%"},1,"55% liquid plasma aur 45% blood cells.",{})
addMCQ("GSN041","General Science","\"Convex Lens\" ko aur kis naam se jana jata hai?",{"Converging Lens","Diverging Lens","Flat Glass","Prism"},1,"Light rays ko aik point par jorta hai.",{})
addMCQ("GSN042","General Science","UV rays ko zameen par aane se kaun rokta hai?",{"Ozone Layer","Troposphere","Ionosphere","Magnetic field only"},1,"Ozone layer UV-B aur UV-C absorb karti hai.",{})
addMCQ("GSN043","General Science","Vitamin A ki kami se kaun si bimari hoti hai?",{"Night Blindness","Scurvy","Rickets","Beriberi"},1,"Raat ko kam dikhna vitamin A ki kami hai.",{})
addMCQ("GSN044","General Science","Insani jism ki sab se bari haddi ka kya naam hai?",{"Femur","Humerus","Tibia","Fibula"},1,"Femur sab se lambi aur mazboot bone hai.",{})
addMCQ("GSN045","General Science","Absolute zero temperature Celsius scale par kitni hoti hai?",{"-273.15C","0C","-100C","-373C"},1,"Is temperature par molecules ki thermal motion khatam ho jati hai.",{})

-- ---------------- History (from user's 500-batch) ----------------
addMCQ("HN011","History","\"Treaty of Nanjing\" (1842) kis jang ke khatme par sign ki gayi thi?",{"First Opium War","Crimean War","Boer War","Franco-Prussian War"},1,"Britain ko Hong Kong ka control mila.",{})

-- ---------------- World General Knowledge (from user's 500-batch) ----------------
addMCQ("WN035","World General Knowledge","\"Strait of Gibraltar\" Atlantic Ocean ko kis samundar se milti hai?",{"Mediterranean Sea","Black Sea","Red Sea","Baltic Sea"},1,"Spain aur Morocco ke darmiyan waqie hai.",{})
addMCQ("WN036","World General Knowledge","\"World Economic Forum\" ka salana jalsa kis shahar mein hota hai?",{"Davos","Geneva","Zurich","Vienna"},1,"Switzerland ke Davos mein hota hai.",{})

-- ---------------- History (from user's 500-batch) ----------------
addMCQ("HN012","History","\"Treaty of Tordesillas\" (1494) ne naye ilaqaajat ko kin do mumalik mein taqseem kiya?",{"Spain aur Portugal","Britain aur France","Netherlands aur Spain","Russia aur Ottoman Empire"},1,"Pope Alexander VI ki mediation ke tehat.",{})

-- ---------------- World General Knowledge (from user's 500-batch) ----------------
addMCQ("WN037","World General Knowledge","\"Kalahari Desert\" zyadatar kis region mein faila hua hai?",{"Southern Africa","North Africa","Australia","South America"},1,"Botswana Namibia South Africa mein.",{})
addMCQ("WN038","World General Knowledge","\"ASEAN\" ka sadar muqam kahan waqie hai?",{"Jakarta","Bangkok","Manila","Singapore"},1,"Indonesia ke Jakarta mein secretariat hai.",{})
addMCQ("WN039","World General Knowledge","\"Suez Canal\" ki lambai qareeban kitni hai?",{"193 km","100 km","300 km","450 km"},1,"Mediterranean aur Red Sea ko milti hai.",{})
addMCQ("WN040","World General Knowledge","ICJ ke faisle ke khilaf appeal kahan ki ja sakti hai?",{"Kahin nahi (Final hota hai)","UN General Assembly","UN Security Council","International Criminal Court"},1,"Faisle final aur binding hote hain.",{})

-- ---------------- History (from user's 500-batch) ----------------
addMCQ("HN013","History","\"Battle of Austerlitz\" (1805) ko aur kis naam se jana jata hai?",{"Battle of the Three Emperors","Battle of Nations","Battle of Waterloo","Battle of Borodino"},1,"Napoleon ki azeem fatah thi.",{})

-- ---------------- World General Knowledge (from user's 500-batch) ----------------
addMCQ("WN041","World General Knowledge","\"Uruguay\" ki capital kya hai?",{"Montevideo","Asuncion","Santiago","Lima"},1,"Uruguay ka capital aur sab se bara shahar hai.",{})

-- ---------------- Constitution & Pak Affairs (from user's 500-batch) ----------------
addMCQ("CNN017","Constitution & Pak Affairs","Pakistan ki pehli Constituent Assembly kis tareeq ko tooti gayi thi?",{"24 October 1954","7 October 1958","25 March 1969","5 July 1977"},1,"Malik Ghulam Muhammad ne dissolve kiya.",{})
addMCQ("CNN018","Constitution & Pak Affairs","Agar President ka ohda khali ho jaye toh kaun acting President banta hai?",{"Chairman of Senate","Speaker of NA","Prime Minister","Chief Justice"},1,"Article 49 ke tehat.",{})

-- ---------------- Pakistan Studies (from user's 500-batch) ----------------
addMCQ("PSN030","Pakistan Studies","Chaudhry Rahmat Ali ne zindagi ke aakhri ayyam kahan guzare thay?",{"England (Cambridge)","Pakistan","Saudi Arabia","India"},1,"1951 mein inteqal England mein hua.",{})
addMCQ("PSN031","Pakistan Studies","Federal Shariat Court ka qiyam kis saal hua?",{"1980","1973","1985","1991"},1,"General Zia-ul-Haq ke dour mein.",{})
addMCQ("PSN032","Pakistan Studies","Liaquat Ali Khan ko kis shahar mein shaheed kiya gaya?",{"Rawalpindi","Lahore","Karachi","Peshawar"},1,"16 October 1951 ko shaheed kiye gaye.",{})
addMCQ("PSN033","Pakistan Studies","Pakistan ka pehla nuclear power plant KANUPP kis shahar mein tha?",{"Karachi","Chashma","Lahore","Islamabad"},1,"1972 mein operational hua.",{})
addMCQ("PSN034","Pakistan Studies","Allama Iqbal ne \"Himalaya\" kis saal likhi?",{"1901","1907","1899","1910"},1,"Makhzan magazine mein shaya hui.",{})
addMCQ("PSN035","Pakistan Studies","1970 ke elections adult franchise par kis framework ke tehat huay?",{"Legal Framework Order","1956 Constitution","1962 Constitution","Direct Order"},1,"Pehli bar direct adult franchise par elections huay.",{})

-- ---------------- Constitution & Pak Affairs (from user's 500-batch) ----------------
addMCQ("CNN019","Constitution & Pak Affairs","1962 ke Ain mein Basic Democrats ki total tadaad kitni thi?",{"80000","40000","50000","100000"},1,"40000 East aur 40000 West Pakistan se.",{})

-- ---------------- Pakistan Studies (from user's 500-batch) ----------------
addMCQ("PSN036","Pakistan Studies","\"Indus Waters Treaty\" (1960) par kis idaray ne mediatorship ki?",{"World Bank","United Nations","IMF","Commonwealth"},1,"Ayub Khan aur Nehru ne Karachi mein sign kiya.",{})

-- ---------------- Islamiyat (from user's 500-batch) ----------------
addMCQ("ISLN046","Islamiyat","Kis Sahabi ko \"Sayyid-ul-Shuhada\" ka laqab diya gaya?",{"Hazrat Hamza","Hazrat Umar","Hazrat Ali","Hazrat Ubaidah"},1,"Jang-e-Uhud mein shahadat ke baad.",{})
addMCQ("ISLN047","Islamiyat","Kis Surah ko \"Qalb-ul-Quran\" kaha jata hai?",{"Surah Yaseen","Surah Al-Mulk","Surah Ar-Rahman","Surah Al-Baqarah"},1,"Har cheez ka dil hota hai, Quran ka dil Yaseen.",{})
addMCQ("ISLN048","Islamiyat","Jang-e-Khandaq kis hijri mein lari gayi thi?",{"5 Hijri","3 Hijri","7 Hijri","8 Hijri"},1,"Shawwal 5 Hijri mein.",{})
addMCQ("ISLN049","Islamiyat","Sahih al-Bukhari ke baad doosri sab se authentic kitab kaun si mani jati hai?",{"Sahih Muslim","Sunan an-Nasa'i","Jami at-Tirmidhi","Sunan Abu Dawud"},1,"Imam Muslim ki likhi hui kitab.",{})
addMCQ("ISLN050","Islamiyat","Kis Khalifa ke dour mein Iran aur Egypt mukammal fatah hue?",{"Hazrat Umar Farooq","Hazrat Abu Bakr","Hazrat Uthman","Hazrat Ali"},1,"Persian aur Byzantine empires fatah hue.",{})
addMCQ("ISLN051","Islamiyat","\"Dar-e-Arqam\" kis maqsad ke liye istemal hota tha?",{"Tableegh ka pehla markaz","Wahi ki jagah","Hijrat ke waqt chupne ki jagah","Jang ka maidan"},1,"Musalman wahan chup kar taleem lete thay.",{})
addMCQ("ISLN052","Islamiyat","Quran-e-Majeed mein kul kitne Para hain?",{"30","20","40","114"},1,"30 paras mein taqseem kiya gaya hai.",{})
addMCQ("ISLN053","Islamiyat","Kis Nabi par \"Torah\" nazil ki gayi thi?",{"Hazrat Musa","Hazrat Isa","Hazrat Dawood","Hazrat Ibrahim"},1,"Hazrat Musa par Taurat nazil hui.",{})
addMCQ("ISLN054","Islamiyat","Namaz-e-Janaza mein takbeerat kitni hoti hain?",{"4 takbeerat","3 takbeerat","5 takbeerat","2 takbeerat"},1,"Ruku sajdah nahi hota.",{})
addMCQ("ISLN055","Islamiyat","Sulah-e-Hudaibiyyah ke moqe par Quraish ki taraf se kon aya tha?",{"Suhail bin Amr","Abu Jahl","Abu Sufiyan","Ikrimah bin Abi Jahl"},1,"Baat cheet ki thi.",{})

-- ---------------- Computer & IT (from user's 500-batch) ----------------
addMCQ("ITN045","Computer & IT","\"DNS\" server ka buniyadi kaam kya hota hai?",{"Domain names ko IP mein translate karna","Computer connect karna","Files download karna","Emails encrypt karna"},1,"Internet ki phonebook kehlata hai.",{})
addMCQ("ITN046","Computer & IT","\"ROM\" ka mukammal matlab kya hai?",{"Read Only Memory","Random Online Module","Rapid Operation Memory","Real Output Machine"},1,"Non-volatile hoti hai.",{})
addMCQ("ITN047","Computer & IT","Excel mein sab se choti value nikalne ke liye kaun sa function use hota hai?",{"MIN()","MAX()","SUM()","COUNT()"},1,"Sab se choti value return karta hai.",{})
addMCQ("ITN048","Computer & IT","\"Spyware\" kis qisam ka software hai?",{"Activities track karta aur data chori karta hai","Speed barhata hai","Internet test karta hai","Games khelne mein madad deta hai"},1,"Harmful malware hai.",{})
addMCQ("ITN049","Computer & IT","IPv4 kitne octets par mushtamil hota hai?",{"4","2","6","8"},1,"Har part octet kehlata hai.",{})
addMCQ("ITN050","Computer & IT","Python mein comments likhne ke liye kis sign ka istamal hota hai?",{"#","//","/* */","--"},1,"Single-line comment '#' se shuru hota hai.",{})
addMCQ("ITN051","Computer & IT","Network mein \"Gateway\" ka kya kaam hota hai?",{"Networks ko connect karna","Aik hi network milana","Printer connect karna","Power regulate karna"},1,"Aik network se doosre par traffic pass karta hai.",{})
addMCQ("ITN052","Computer & IT","\"SSD\" HDD se kis tarah behtar hai?",{"Tez hoti hai aur moving parts nahi","Cost kam hoti hai","Life infinite hoti hai","Sirf data delete karti hai"},1,"Flash memory use karti hai.",{})
addMCQ("ITN053","Computer & IT","HTML mein line break ke liye kaun sa tag use hota hai?",{"br tag","p tag","hr tag","b tag"},1,"Agli line par jane ke liye.",{})
addMCQ("ITN054","Computer & IT","Database mein SQL ka main function kya hota hai?",{"Databases ko query aur manage karna","Hardware design karna","Web pages banana","OS boot karna"},1,"Data insert update delete select karta hai.",{})

-- ---------------- General Science (from user's 500-batch) ----------------
addMCQ("GSN046","General Science","RBCs ki average life kitni hoti hai?",{"120 days","30 days","365 days","7 days"},1,"Spleen aur liver mein destroy hote hain.",{})
addMCQ("GSN047","General Science","\"Hygrometer\" kis cheez ko maapne ke liye istemal hota hai?",{"Humidity","Wind speed","Air pressure","Temperature"},1,"Atmosphere ki humidity maapi jati hai.",{})
addMCQ("GSN048","General Science","\"Avogadro's Number\" ki value kitni hoti hai?",{"6.022x10^23","3x10^8","9.8 m/s^2","1.6x10^-19"},1,"Aik mole mein particles ki tadaad.",{})
addMCQ("GSN049","General Science","Suraj ki roshni mein kitne primary colors shamil hote hain?",{"7 colors","3 colors","5 colors","12 colors"},1,"VIBGYOR - prism se guzarne par.",{})
addMCQ("GSN050","General Science","\"Thyroid Gland\" kahan waqie hoti hai?",{"Neck","Brain","Chest","Stomach"},1,"Metabolism control karti hai.",{})
addMCQ("GSN051","General Science","Heavy Water ka freezing point aam pani se kaisa hota hai?",{"Thora zyadah (3.8C)","0C hi hota hai","-10C hota hai","Kabhi nahi jamta"},1,"D2O 3.8C par freeze hota hai.",{})
addMCQ("GSN052","General Science","Gravity ki standard value kitni hoti hai?",{"9.8 m/s^2","3.2 m/s^2","11.2 m/s^2","5.5 m/s^2"},1,"Zameen ki gravitational pull.",{})
addMCQ("GSN053","General Science","Vitamin E ka chemical name kya hai?",{"Tocopherol","Retinol","Ascorbic Acid","Thiamine"},1,"Skin aur cell health ke liye zaroori.",{})
addMCQ("GSN054","General Science","Pancreas kis tarah ka organ hai?",{"Dono Mixed gland","Sirf endocrine","Sirf exocrine","Koi bhi nahi"},1,"Enzymes aur hormones dono banata hai.",{})
addMCQ("GSN055","General Science","Universe ki expansion sab se pehle kis scientist ne prove ki?",{"Edwin Hubble","Albert Einstein","Stephen Hawking","Isaac Newton"},1,"Hubble's law ke tehat galaxies door ja rahi hain.",{})

-- ---------------- History (from user's 500-batch) ----------------
addMCQ("HN014","History","\"Treaty of Portsmouth\" (1905) kis jang ko khatam karne ke liye sign ki gayi thi?",{"Russo-Japanese War","World War I","Franco-Prussian War","Opium War"},1,"US President Theodore Roosevelt ki mediation.",{})

-- ---------------- World General Knowledge (from user's 500-batch) ----------------
addMCQ("WN042","World General Knowledge","\"Strait of Magellan\" kis continent ke southern tip par waqie hai?",{"South America","Africa","Australia","North America"},1,"Atlantic aur Pacific Ocean ke darmiyan.",{})
addMCQ("WN043","World General Knowledge","\"International Criminal Court\" ka headquarters kahan hai?",{"The Hague","Geneva","New York","Vienna"},1,"War crimes ke mukadmaat chalaati hai.",{})

-- ---------------- History (from user's 500-batch) ----------------
addMCQ("HN015","History","\"Berlin Conference\" (1884-1885) ka maqsad kis continent ki taqseem thi?",{"Africa","Asia","South America","Oceania"},1,"European powers ne African continent baanta.",{})

-- ---------------- World General Knowledge (from user's 500-batch) ----------------
addMCQ("WN044","World General Knowledge","\"Taklamakan Desert\" kis famous route par waqie hai?",{"Silk Road","Spice Route","Amber Road","Incense Route"},1,"Central Asia mein Silk Road ke paas.",{})
addMCQ("WN045","World General Knowledge","SAARC ka pehla summit kis saal aur kahan hua?",{"1985 Dhaka","1980 Islamabad","1990 New Delhi","1988 Kathmandu"},1,"December 1985 mein pehla summit.",{})
addMCQ("WN046","World General Knowledge","\"Baikal Lake\" duniya ki sab se gahri lake, kis mulk mein hai?",{"Russia","Canada","United States","China"},1,"Freshwater ke lihaz se sab se bari lake.",{})

-- ---------------- History (from user's 500-batch) ----------------
addMCQ("HN016","History","\"Treaty of Westphalia\" kis saal sign hui jis ne modern nation-state system banaya?",{"1648","1789","1515","1815"},1,"Thirty Years' War ke khatme par.",{})
addMCQ("HN017","History","\"Battle of Gettysburg\" (1863) kis civil war se hai?",{"American Civil War","English Civil War","Spanish Civil War","Russian Civil War"},1,"Sab se khooni jang mani jati hai.",{})

-- ---------------- World General Knowledge (from user's 500-batch) ----------------
addMCQ("WN047","World General Knowledge","\"Ulaanbaatar\" kis mulk ka capital hai?",{"Mongolia","Kazakhstan","Uzbekistan","Kyrgyzstan"},1,"Mongolia ka sab se bara shahar.",{})

-- ---------------- Pakistan Studies (from user's 500-batch) ----------------
addMCQ("PSN037","Pakistan Studies","1954 mein Maulvi Tamizuddin Khan ke case mein unke lawyer kaun thay?",{"H.S. Suhrawardy","Zulfikar Ali Bhutto","A.K. Brohi","Manzur Qadir"},1,"Suhrawardy ne case ki pairwi ki.",{})
addMCQ("PSN038","Pakistan Studies","Council of Islamic Ideology (CII) ka buniyadi kaam kya hai?",{"Laws ko Quran Sunnah ke mutabiq recommendations dena","Judges appoint karna","Zakat collect karna","Foreign policy banana"},1,"Advisory body hai.",{})
addMCQ("PSN039","Pakistan Studies","\"Armaghan-e-Hijaz\" mein urdu ka hissa kitna hai?",{"Aik-chothai hissa","Saari urdu","Sirf farsi","Adhi adhi"},1,"Farsi ke sath urdu nazmein bhi shamil.",{})

-- ---------------- Constitution & Pak Affairs (from user's 500-batch) ----------------
addMCQ("CNN020","Constitution & Pak Affairs","Provincial Autonomy ko sab se ziyada wusat kis amendment se di gayi?",{"18th Amendment","8th Amendment","17th Amendment","21st Amendment"},1,"2010 mein Concurrent List khatam ki gayi.",{})
addMCQ("CNN021","Constitution & Pak Affairs","1956 ke ain ke tehat pehla Constitutional President kaun bana?",{"Iskander Mirza","Ayub Khan","Ghulam Muhammad","Ch. Muhammad Ali"},1,"23 March 1956 ko bane.",{})

-- ---------------- Pakistan Studies (from user's 500-batch) ----------------
addMCQ("PSN040","Pakistan Studies","\"Sukkur Barrage\" ka irtetah kis saal kiya gaya?",{"1932","1947","1950","1925"},1,"January 1932 mein hua.",{})
addMCQ("PSN041","Pakistan Studies","Quaid-e-Azam ne aakhri taqreer kis idaray ke irtetah par ki?",{"State Bank of Pakistan","University of Punjab","Karachi Port Trust","Radio Pakistan"},1,"1 July 1948 ko.",{})

-- ---------------- Constitution & Pak Affairs (from user's 500-batch) ----------------
addMCQ("CNN022","Constitution & Pak Affairs","Fundamental Rights ko 1962 ke ain ka hissa kis tarmeem se banaya gaya?",{"First Constitutional Amendment 1963","Eighth Amendment","Second Amendment","Fourth Amendment"},1,"Shuru mein direct hissa nahi thay.",{})

-- ---------------- Pakistan Studies (from user's 500-batch) ----------------
addMCQ("PSN042","Pakistan Studies","Thar desert kis province mein waqie hai?",{"Sindh","Punjab","Balochistan","Khyber Pakhtunkhwa"},1,"Thar ka bara hissa Sindh mein hai.",{})
addMCQ("PSN043","Pakistan Studies","Liaquat-Nehru Pact kis shahar mein sign hua?",{"New Delhi","Karachi","Lahore","Dhaka"},1,"April 1950 mein.",{})

-- ---------------- Islamiyat (from user's 500-batch) ----------------
addMCQ("ISLN056","Islamiyat","Kis Sahabi ko \"Ameen-e-Ummat\" ka laqab diya gaya?",{"Abu Ubaidah bin al-Jarrah","Zaid bin Harithah","Saad bin Abi Waqas","Talha bin Ubaidullah"},1,"Najran ke logon ki darkhwast par.",{})
addMCQ("ISLN057","Islamiyat","\"Surah Al-Mumtahanah\" ka kya matlab hai?",{"Imtehan li gayi aurat","Mominon ki surah","Fatah ki surah","Sabr ki surah"},1,"Surah No. 60.",{})
addMCQ("ISLN058","Islamiyat","Jang-e-Mu'tah kis hijri mein lari gayi thi?",{"8 Hijri","7 Hijri","9 Hijri","6 Hijri"},1,"Zaid bin Harithah ne qiyadat shuru ki.",{})
addMCQ("ISLN059","Islamiyat","Sahih al-Bukhari ki pehli hadees kis mozu par hai?",{"Niyaton par aamal ka daromadar","Namaz ki ahmiyat","Iman ki shartein","Hajj ke ahkaam"},1,"Innamal aamalu bin niyyat.",{})
addMCQ("ISLN060","Islamiyat","Kis Khalifa ke daur mein naval fleet pehli baar tayar hui?",{"Hazrat Uthman bin Affan","Hazrat Umar Farooq","Hazrat Ali","Hazrat Abu Bakr"},1,"Muawiyah ne Islamic navy banai.",{})
addMCQ("ISLN061","Islamiyat","Kis Surah mein Bismillah shuru mein nahi hai?",{"Surah At-Tawbah","Surah Al-Baqarah","Surah An-Naml","Surah Al-Maidah"},1,"Wahid surah jiske aaghaz mein Bismillah nahi.",{})
addMCQ("ISLN062","Islamiyat","Pehla para kis surah se shuru hota hai?",{"Surah Al-Fatihah aur Al-Baqarah","Surah Al-Imran","Surah An-Nisa","Surah Al-Maidah"},1,"Manzil ki taqseem ke mutabiq.",{})
addMCQ("ISLN063","Islamiyat","Khaibar mein kis yahoodi pehlwan ko Hazrat Ali ne shikast di?",{"Marhab","Huyayy bin Akhtab","Kaab ibn al-Ashraf","Sallam ibn Abu al-Huqayq"},1,"Khaibar ke qile ke maidan mein.",{})
addMCQ("ISLN064","Islamiyat","Kis Nabi ko \"Ruhullah\" ka laqab bhi diya gaya?",{"Hazrat Isa","Hazrat Musa","Hazrat Ibrahim","Hazrat Yahya"},1,"Quran mein Ruhullah kaha gaya.",{})
addMCQ("ISLN065","Islamiyat","Namaz-e-Kusoof mein kitne rakat hote hain?",{"Aam namaz ki tarah do rakat","Ruku do bar har rakat","Sajday chaar hote","Ruku aur sajdah nahi"},1,"Hanafi fiqh ke mutabiq.",{})

-- ---------------- Computer & IT (from user's 500-batch) ----------------
addMCQ("ITN055","Computer & IT","\"FTP\" kis port par kaam karta hai?",{"Port 20 aur 21","Port 80","Port 443","Port 53"},1,"Data transfer aur control connection.",{})
addMCQ("ITN056","Computer & IT","Computer ki Fifth Generation mein kis technology par kaam ho raha hai?",{"Artificial Intelligence aur Quantum Computing","Vacuum Tubes","Transistors","Integrated Circuits"},1,"AI aur neural networks.",{})
addMCQ("ITN057","Computer & IT","Excel mein #N/A error ka kya matlab hota hai?",{"Value is not available","Zero se division","Spelling galat","Column width choti"},1,"Lookup function ko target value nahi milti.",{})
addMCQ("ITN058","Computer & IT","\"Adware\" kis qisam ka software hota hai?",{"Unwanted ads show karta hai","Antivirus protect karta hai","Speed barhata hai","Hard disk clean karta hai"},1,"Free software ke sath install ho jata hai.",{})
addMCQ("ITN059","Computer & IT","IPv6 kis numbering system mein likha jata hai?",{"Hexadecimal","Decimal","Binary","Octal"},1,"Colons se separated blocks mein.",{})
addMCQ("ITN060","Computer & IT","Python mein function define karne ke liye kis keyword ka istemal hota hai?",{"def","function","fun","define"},1,"def function_name(): likh kar.",{})
addMCQ("ITN061","Computer & IT","Firewall ka buniyadi kaam kya hota hai?",{"Unauthorized access rokna","Computer thanda rakhna","Internet speed tezz karna","Files back up karna"},1,"Security guard ka kaam karta hai.",{})
addMCQ("ITN062","Computer & IT","SSD mein data read/write karne ke liye kis technology ka istemal hota hai?",{"NAND Flash Memory","Magnetic spinning platters","Optical laser discs","Vacuum glass tubes"},1,"Koi mechanical part nahi hota.",{})
addMCQ("ITN063","Computer & IT","Database mein DDL ka mukammal matlab kya hota hai?",{"Data Definition Language","Data Direct Link","Database Design Logic","Digital Data Language"},1,"CREATE ALTER DROP commands.",{})

-- ---------------- General Science (from user's 500-batch) ----------------
addMCQ("GSN056","General Science","WBCs ka asal buniyadi kaam kya hota hai?",{"Immune system mazboot karna","Oxygen transport karna","Khoon jamana","Body temperature maintain karna"},1,"Jism ke defense system ka hissa hain.",{})
addMCQ("GSN057","General Science","\"Seismograph\" kis phenomenon ko record karta hai?",{"Earthquakes","Volcanic eruptions","Tornadoes","Ocean waves"},1,"Zalzale ki waves record ki jati hain.",{})
addMCQ("GSN058","General Science","pH ka mukammal matlab kya hota hai?",{"Potential of Hydrogen","Pure Hydrogen","Proton Hardness","Pressure of Heat"},1,"Acidity ya alkalinity measure karta hai.",{})
addMCQ("GSN059","General Science","Sunlight mein skin exposure se kaun sa vitamin paida hota hai?",{"Vitamin D","Vitamin C","Vitamin A","Vitamin K"},1,"Skin vitamin D synthesize karti hai.",{})
addMCQ("GSN060","General Science","Insani jism ki sab se bari artery ka naam kya hai?",{"Aorta","Vena Cava","Pulmonary Artery","Capillary"},1,"Dil se poore jism mein khoon pohnchati hai.",{})
addMCQ("GSN061","General Science","Heavy Water ka boiling point aur freezing point kaisa hota hai?",{"Dono zyadah hote hain","Dono kam hote hain","Dono same hote hain","Koi taluq nahi"},1,"Boiling point 101.4C hota hai.",{})
addMCQ("GSN062","General Science","Sound waves kis qisam ki hoti hain?",{"Longitudinal waves","Transverse waves","Electromagnetic waves","Stationary waves only"},1,"Compression aur rarefaction ke zariye.",{})
addMCQ("GSN063","General Science","Vitamin K ki kami se kya nuqsaan hota hai?",{"Khoon ka na jamna","Night blindness","Rickets","Scurvy"},1,"Blood coagulation ke liye zaroori.",{})
addMCQ("GSN064","General Science","\"Pituitary Gland\" kahan waqie hoti hai?",{"Base of the Brain","Neck","Chest","Jigar ke paas"},1,"Master Gland kehlati hai.",{})
addMCQ("GSN065","General Science","Einstein ko 1921 Nobel Prize kis theory par mila?",{"Photoelectric Effect","Theory of Relativity","Mass-Energy Equivalence","Quantum Mechanics"},1,"Relativity mashhoor hai lekin Nobel Photoelectric par mila.",{})

-- ---------------- History (from user's 500-batch) ----------------
addMCQ("HN018","History","Treaty of Versailles ke tehat kis mulk par jang ki zimmedari dali gayi?",{"Germany","Austria-Hungary","Ottoman Empire","Bulgaria"},1,"War Guilt Clause Article 231.",{})

-- ---------------- World General Knowledge (from user's 500-batch) ----------------
addMCQ("WN048","World General Knowledge","Strait of Malacca kin do oceans ke darmiyan ahem trade route hai?",{"Indian Ocean aur Pacific Ocean","Atlantic aur Pacific","Red Sea aur Mediterranean","Persian Gulf aur Arabian Sea"},1,"Malaysia aur Indonesia ke darmiyan.",{})
addMCQ("WN049","World General Knowledge","Amnesty International ka headquarters kahan hai?",{"London","Geneva","Paris","New York"},1,"Human rights ke tahafuz ke liye kaam karti hai.",{})

-- ---------------- History (from user's 500-batch) ----------------
addMCQ("HN019","History","Yalta Conference (1945) mein kis idaray ki buniyad par baat hui?",{"United Nations","League of Nations","European Union","NATO"},1,"Churchill Roosevelt Stalin ne conference ki.",{})

-- ---------------- World General Knowledge (from user's 500-batch) ----------------
addMCQ("WN050","World General Knowledge","Atacama Desert kis bar-e-azam mein hai?",{"South America","Africa","Australia","Asia"},1,"Chile ki hudood mein waqie hai.",{})
addMCQ("WN051","World General Knowledge","OPEC ka current headquarters kahan hai?",{"Vienna","Geneva","Riyadh","Doha"},1,"OPEC ka secretariat Austria mein hai.",{})
addMCQ("WN052","World General Knowledge","Casablanca kis mulk ka ahem port city hai?",{"Morocco","Egypt","Algeria","Tunisia"},1,"Morocco ka sab se bara shahar.",{})
addMCQ("WN053","World General Knowledge","ICJ ke judges ki total tadaad aur term kitni hoti hai?",{"15 judges 9 years","10 judges 5 years","21 judges 7 years","12 judges 6 years"},1,"UN General Assembly aur Security Council ke zariye muntakhab.",{})

-- ---------------- History (from user's 500-batch) ----------------
addMCQ("HN020","History","Battle of Waterloo mein Napoleon ko kis British general ne shikast di?",{"Duke of Wellington","Admiral Nelson","General Cornwallis","Field Marshal Montgomery"},1,"Napoleon ka fatihana daur khatam hua.",{})

-- ---------------- World General Knowledge (from user's 500-batch) ----------------
addMCQ("WN054","World General Knowledge","Baku kis mulk ka capital hai?",{"Azerbaijan","Armenia","Georgia","Turkmenistan"},1,"Caspian basin ka ahem shahar.",{})

-- ---------------- Constitution & Pak Affairs (from user's 500-batch) ----------------
addMCQ("CNN023","Constitution & Pak Affairs","Malik Ghulam Muhammad ne pehli baar kis Assembly ko tooti thi?",{"Malik Ghulam Muhammad ne assembly tooti","Iskander Mirza","Khawaja Nazimuddin","Ayub Khan"},1,"October 1954 mein Constituent Assembly dissolve ki.",{})
addMCQ("CNN024","Constitution & Pak Affairs","Provincial breakdown par Governor Rule kis Article ke tehat lagta hai?",{"Article 234","Article 144","Article 153","Article 6"},1,"Constitutional machinery fail hone par.",{})
addMCQ("CNN025","Constitution & Pak Affairs","Shikwa aur Jawab-e-Shikwa kis kitab ka hissa hain?",{"Baang-e-Dra","Bal-e-Jibreel","Zarb-e-Kalim","Armaghan-e-Hijaz"},1,"1909 aur 1913 mein likhi gayin.",{})

-- ---------------- Pakistan Studies (from user's 500-batch) ----------------
addMCQ("PSN044","Pakistan Studies","National Finance Commission (NFC) Award ka kaam kya hota hai?",{"Revenue ki taqseem karna","Note print karna","Interest rates tay karna","Foreign loans negotiate karna"},1,"Article 160 ke tehat.",{})
addMCQ("PSN045","Pakistan Studies","Pakistan ke pehle Foreign Minister kaun thay?",{"Sir Zafarulla Khan","Liaquat Ali Khan","H.S. Suhrawardy","Jogendra Nath Mandal"},1,"Pehle foreign minister thay.",{})
addMCQ("PSN046","Pakistan Studies","Warsak Dam kis subay aur darya par hai?",{"KPK River Kabul","Sindh Indus","Punjab Jhelum","Balochistan Bolan"},1,"1960 mein Peshawar ke qareeb mukammal hua.",{})
addMCQ("PSN047","Pakistan Studies","Quaid-e-Azam ne Muslim League ki sadarat dobara kab sambhali?",{"1934","1906","1940","1920"},1,"London se wapasi par.",{})

-- ---------------- Constitution & Pak Affairs (from user's 500-batch) ----------------
addMCQ("CNN026","Constitution & Pak Affairs","1962 ke Ain ke tehat mulk ka naam shuru mein kya tha?",{"Republic of Pakistan","Islamic Republic of Pakistan","Islamic State of Pakistan","Federal Pakistan"},1,"Baad mein tarmeem se Islamic joda gaya.",{})

-- ---------------- Pakistan Studies (from user's 500-batch) ----------------
addMCQ("PSN048","Pakistan Studies","Pakistan ka sab se chota suba area ke lihaz se kaunsa hai?",{"Khyber Pakhtunkhwa","Sindh","Balochistan","Punjab"},1,"4 baray sobon mein sab se chota.",{})
addMCQ("PSN049","Pakistan Studies","Radcliffe Award kis din public kiya gaya?",{"17 August 1947","14 August 1947","15 August 1947","10 July 1947"},1,"Independence ke do din baad.",{})

-- ---------------- Islamiyat (from user's 500-batch) ----------------
addMCQ("ISLN066","Islamiyat","Kis Sahabi ko \"Saifullah\" ka laqab diya gaya?",{"Hazrat Khalid bin Walid","Hazrat Ali","Hazrat Umar","Hazrat Hamza"},1,"Jang-e-Mu'tah mein hikmat-e-amli par.",{})
addMCQ("ISLN067","Islamiyat","Kis Surah ko \"Aroos-ul-Quran\" kaha jata hai?",{"Surah Ar-Rahman","Surah Yaseen","Surah Al-Mulk","Surah Al-Waqiah"},1,"Quran ki dulhan kaha jata hai.",{})
addMCQ("ISLN068","Islamiyat","Sulah-e-Hudaibiyyah kis hijri mein tay payi?",{"6 Hijri","5 Hijri","7 Hijri","8 Hijri"},1,"Zulkadah 6 Hijri mein.",{})
addMCQ("ISLN069","Islamiyat","Imam Muslim ka taluq kis shahar se tha?",{"Nishapur","Bukhara","Baghdad","Medina"},1,"Iran mein 204 Hijri janam hua.",{})
addMCQ("ISLN070","Islamiyat","Bait-ul-Mal ka formal nizam kis Khalifa ke daur mein qayam hua?",{"Hazrat Umar Farooq","Hazrat Abu Bakr","Hazrat Uthman","Hazrat Ali"},1,"Salary system ki buniyad rakhi.",{})
addMCQ("ISLN071","Islamiyat","Kitne aayat-e-sajda hain aur kitni wajib hain?",{"14 sab wajib","10","20","7"},1,"Fiqh-e-Hanafi ke mutabiq.",{})
addMCQ("ISLN072","Islamiyat","Quran ki manzil ki taqseem mein total kitni manzilain hoti hain?",{"7","30","10","4"},1,"Hafte mein khatam karne ke liye.",{})
addMCQ("ISLN073","Islamiyat","Jang-e-Ahzaab mein muhasra kitne din raha?",{"27 se 30 din","3 din","10 din","3 mahine"},1,"Madina ka muhasra taqreeban aik maheena.",{})
addMCQ("ISLN074","Islamiyat","Kis Nabi par Zaboor nazil hui?",{"Hazrat Dawood","Hazrat Musa","Hazrat Isa","Hazrat Ibrahim"},1,"David par Zaboor nazil hui.",{})
addMCQ("ISLN075","Islamiyat","Namaz-e-Janaza mein kya padha jata hai?",{"Sana Durood aur dua","Surah Fatihah laazmi","Koi nahi","Sirf tasbeeh"},1,"Ruku sajdah nahi hota.",{})

-- ---------------- Computer & IT (from user's 500-batch) ----------------
addMCQ("ITN064","Computer & IT","SMTP kis port par email bhejta hai?",{"Port 25 ya 587","Port 80","Port 443","Port 21"},1,"Email transfer ke liye.",{})
addMCQ("ITN065","Computer & IT","Computer ki First Generation mein kya use hota tha?",{"Vacuum Tubes","Transistors","Integrated Circuits","Microprocessors"},1,"1940s se 1950s tak.",{})
addMCQ("ITN066","Computer & IT","VLOOKUP mein FALSE likhne ka kya maqsad hai?",{"Exact match dhoondna","Approximate match","Error ignore karna","Ascending sort karna"},1,"Sirf exact match return karta hai.",{})
addMCQ("ITN067","Computer & IT","Trojan Horse kis qisam ka malware hai?",{"Useful file zahir karta hai lekin malware hota hai","Speed slow karta hai","Screen lock karta hai","Hardware jalata hai"},1,"Greek kahani se naam.",{})
addMCQ("ITN068","Computer & IT","MAC Address kitne bits ka hota hai?",{"48 bits","32 bits","128 bits","64 bits"},1,"Hexadecimal mein hota hai.",{})
addMCQ("ITN069","Computer & IT","Python mein lists banane ke liye kis bracket ka istemal hota hai?",{"Square brackets","Curly braces","Parentheses","Angle brackets"},1,"Mutable lists [] se banti hain.",{})
addMCQ("ITN070","Computer & IT","Router aur Switch mein kya farq hai?",{"Router alag networks milata Switch aik hi network","Router sirf wireless","Dono same","Switch sirf hardware"},1,"Router IP addresses ki base par.",{})
addMCQ("ITN071","Computer & IT","Blu-ray single-layer capacity kitni hoti hai?",{"25 GB","700 MB","4.7 GB","70 GB"},1,"DVD se zyadah storage deti hai.",{})
addMCQ("ITN072","Computer & IT","HTML mein image insert karne ke liye kaun sa tag hai?",{"img tag","image tag","pic tag","src tag"},1,"src attribute ke sath use hota hai.",{})
addMCQ("ITN073","Computer & IT","DML ki ahem misalein kya hain?",{"SELECT INSERT UPDATE DELETE","CREATE DROP ALTER","GRANT REVOKE","Koi nahi"},1,"Data manipulate karne ke liye.",{})

-- ---------------- General Science (from user's 500-batch) ----------------
addMCQ("GSN066","General Science","Platelets ka buniyadi kaam kya hota hai?",{"Khoon jamana","Oxygen lana","Immunity barhana","Digestion karna"},1,"Zakhmi hone par behne se rokte hain.",{})
addMCQ("GSN067","General Science","Barometer kis quantity ko maapta hai?",{"Atmospheric Pressure","Wind speed","Humidity","Rainfall"},1,"Mosam ki peshingoi mein kaam aata hai.",{})
addMCQ("GSN068","General Science","pH 7 se kam ho toh solution kaisa hota hai?",{"Acidic","Basic","Neutral","Pure Salt"},1,"7 neutral hota hai.",{})
addMCQ("GSN069","General Science","Kaun si rays skin ko tan ya burn kar sakti hain?",{"Ultraviolet Rays","Infrared Rays","X-rays","Gamma rays"},1,"UV-A aur UV-B asar andaz hoti hain.",{})
addMCQ("GSN070","General Science","Insani jism ki sab se choti bone kahan hai?",{"Kaano ke andar Stapes","Naak mein","Ungliyon mein","Ankhoon ke paas"},1,"Middle ear mein hoti hai.",{})
addMCQ("GSN071","General Science","Heavy Water mein hydrogen ka kaunsa isotope hota hai?",{"Deuterium","Tritium","Protium","Alpha particle"},1,"Heavy hydrogen kehlata hai.",{})
addMCQ("GSN072","General Science","Vitamin B12 ki kami se kya masla hota hai?",{"Pernicious Anemia","Night blindness","Scurvy","Rickets"},1,"Nervous system ke liye zaroori.",{})
addMCQ("GSN073","General Science","Liver blood se ammonia ko kis mein badalta hai?",{"Urea","Carbon dioxide","Lactic acid","Cholesterol"},1,"Proteins ki breakdown se banti hai.",{})
addMCQ("GSN074","General Science","Newton ka konsa law \"Law of Inertia\" kehlata hai?",{"First Law","Second Law","Third Law","Law of Gravitation"},1,"External force na lagne tak halat nahi badalti.",{})

-- ---------------- History (from user's 500-batch) ----------------
addMCQ("HN021","History","Treaty of Lausanne (1923) ne kis empire ki modern boundaries tasleem karwayin?",{"Republic of Turkey","Austro-Hungarian Empire","Russian Empire","Qajar Empire"},1,"Ottoman Empire ke baad Lausanne muhaide se.",{})

-- ---------------- World General Knowledge (from user's 500-batch) ----------------
addMCQ("WN055","World General Knowledge","Strait of Dover kin do mumalik ko alag karti hai?",{"Britain aur France","Spain aur Morocco","US aur Russia","Italy aur Greece"},1,"English Channel ka narrow point.",{})
addMCQ("WN056","World General Knowledge","WHO ka headquarters kahan waqie hai?",{"Geneva","Vienna","Paris","New York"},1,"UN ki specialized agency public health ke liye.",{})

-- ---------------- History (from user's 500-batch) ----------------
addMCQ("HN022","History","Potsdam Conference mein kin leaders ne faisla kiya?",{"Truman Churchill Attlee Stalin","Roosevelt Hitler","Napoleon Alexander","Mussolini Stalin"},1,"Germany ki defeat ke baad conference.",{})

-- ---------------- World General Knowledge (from user's 500-batch) ----------------
addMCQ("WN057","World General Knowledge","Gobi Desert kis region mein waqie hai?",{"China aur Mongolia","North Africa","Australia","South America"},1,"Asia ka rain-shadow desert.",{})
addMCQ("WN058","World General Knowledge","SAARC ka permanent secretariat kahan hai?",{"Kathmandu","Islamabad","New Delhi","Dhaka"},1,"1987 mein qayam kiya gaya.",{})
addMCQ("WN059","World General Knowledge","Caspian Sea ka pani kis qisam ka hai?",{"Khara pani","Meetha pani","Distilled water","Barf wala pani"},1,"Dunya ki sab se bari inland body of water.",{})
addMCQ("WN060","World General Knowledge","League of Nations kis saal qaim hui?",{"1920","1945","1914","1899"},1,"Treaty of Versailles ke tehat.",{})

-- ---------------- History (from user's 500-batch) ----------------
addMCQ("HN023","History","Battle of Trafalgar mein British admiral kaun shaheed huay?",{"Admiral Horatio Nelson","Admiral Drake","Admiral Collingwood","Admiral Rodney"},1,"Naval supremacy tareekhi thi.",{})

-- ---------------- World General Knowledge (from user's 500-batch) ----------------
addMCQ("WN061","World General Knowledge","Reykjavik kis mulk ka northernmost capital hai?",{"Iceland","Norway","Finland","Sweden"},1,"Iceland ka sab se bara shahar.",{})

-- ---------------- Pakistan Studies (from user's 500-batch) ----------------
addMCQ("PSN050","Pakistan Studies","Sindh Chief Court ke faisle ko Federal Court mein kis ne palat diya?",{"Justice Muhammad Munir","Justice A.R. Cornelius","Justice Abdul Rashid","Justice Shahabuddin"},1,"Doctrine of Necessity ke tehat.",{})

-- ---------------- Constitution & Pak Affairs (from user's 500-batch) ----------------
addMCQ("CNN027","Constitution & Pak Affairs","Senate mein har province se kitne members hote hain?",{"23 members per province","10 members","15 members","30 members"},1,"Fata merger ke baad.",{})

-- ---------------- Pakistan Studies (from user's 500-batch) ----------------
addMCQ("PSN051","Pakistan Studies","Allama Iqbal ka mazar kahan waqie hai?",{"Lahore Badshahi Masjid ke qareeb","Sialkot","Islamabad","Karachi"},1,"Shahi Qila ke darmiyan.",{})

-- ---------------- Constitution & Pak Affairs (from user's 500-batch) ----------------
addMCQ("CNN028","Constitution & Pak Affairs","CCI ka constitutional reference kis article mein hai?",{"Article 153","Article 140A","Article 184(3)","Article 62"},1,"Disputes resolve karne ke liye.",{})

-- ---------------- Pakistan Studies (from user's 500-batch) ----------------
addMCQ("PSN052","Pakistan Studies","Pehle Pakistani Commander-in-Chief kaun thay?",{"General Ayub Khan","General Musa Khan","General Tikka Khan","Field Marshal Ayub Khan"},1,"1951 mein Messervy ke baad bane.",{})
addMCQ("PSN053","Pakistan Studies","Tarbela Dam kis darya par aur kab mukammal hua?",{"River Indus 1976","River Jhelum","River Chenab","River Kabul"},1,"Dunya ka sab se bara earth-filled dam.",{})
addMCQ("PSN054","Pakistan Studies","Lahore Resolution ki sadarat Quaid-e-Azam ne kis haisiyat se ki?",{"President of All-India Muslim League","Chief Minister","Governor General","Special Guest"},1,"23 March 1940 ke jalsay mein.",{})

-- ---------------- Constitution & Pak Affairs (from user's 500-batch) ----------------
addMCQ("CNN029","Constitution & Pak Affairs","1962 ka Ain kis tareeq ko aur kis ne mansookh kiya?",{"25 March 1969 Yahya Khan","5 July 1977","7 October 1958","24 March 1969"},1,"Ayub Khan ke baad Yahya Khan ne khatam kiya.",{})

-- ---------------- Pakistan Studies (from user's 500-batch) ----------------
addMCQ("PSN055","Pakistan Studies","Pakistan ka sab se bara district area ke lihaz se kaunsa hai?",{"Chaghi","Khuzdar","Bahawalpur","Thar"},1,"Nuclear tests bhi wahan hue.",{})
addMCQ("PSN056","Pakistan Studies","Simla Agreement par Bhutto aur kis Indian PM ne dastakhat kiye?",{"Indira Gandhi","Jawaharlal Nehru","Lal Bahadur Shastri","Morarji Desai"},1,"1971 ki jang ke baad.",{})

-- ---------------- Islamiyat (from user's 500-batch) ----------------
addMCQ("ISLN076","Islamiyat","Kis Sahabi ko \"Tarjuman-ul-Quran\" ka laqab mila?",{"Hazrat Abdullah bin Abbas","Hazrat Abdullah bin Umar","Hazrat Zaid bin Sabit","Hazrat Ubayy bin Kaab"},1,"Nabi ki dua ki wajah se.",{})
addMCQ("ISLN077","Islamiyat","Ashab-e-Kahf ka qissa kis Surah mein hai?",{"Surah Al-Kahf","Surah Maryam","Surah Yaseen","Surah Al-Mulk"},1,"Jumma ke din parhne ki fazilat.",{})
addMCQ("ISLN078","Islamiyat","Jang-e-Tabuk kis hijri mein aur kis ke khilaf thi?",{"9 Hijri Roman Empire","8 Hijri","7 Hijri","10 Hijri"},1,"Aakhri ghazwa jismein jang nahi hui.",{})
addMCQ("ISLN079","Islamiyat","Imam An-Nasa'i kahan ke rehne wale thay?",{"Nasa Khorasan region","Imam Bukhari","Imam Muslim","Imam Tirmidhi"},1,"Turkmenistan mein.",{})
addMCQ("ISLN080","Islamiyat","Kis Khalifa ke daur mein Quran ko standard mushaf mein jama kiya gaya?",{"Hazrat Uthman bin Affan","Hazrat Abu Bakr","Hazrat Umar","Hazrat Ali"},1,"Official standardization.",{})
addMCQ("ISLN081","Islamiyat","Kitni Makki aur kitni Madani Surah hain?",{"86 Makki 28 Madani","90 Makki 24 Madani","100 Makki 14 Madani","80 Makki 34 Madani"},1,"Total 114 Surahs.",{})
addMCQ("ISLN082","Islamiyat","Quran ka sab se lamba para kaunsa hai?",{"Para No. 2","Para 1","Para 30","Para 15"},1,"Surah Baqarah ki aakhri ayaat se shuru.",{})
addMCQ("ISLN083","Islamiyat","Fateh Makkah kis hijri mein hui?",{"8 Hijri","7 Hijri","6 Hijri","9 Hijri"},1,"Bagair kisi jang ke fatah hui.",{})
addMCQ("ISLN084","Islamiyat","Kis Nabi par Sahifay nazil huay?",{"Hazrat Ibrahim","Hazrat Musa","Hazrat Isa","Hazrat Dawood"},1,"Suhuf-e-Ibrahim wa Musa.",{})
addMCQ("ISLN085","Islamiyat","Namaz-e-Janaza mein haath kab uthaye jate hain?",{"Har takbeer par","Har rakat mein","Ruku mein","Sajday mein"},1,"Rafa ul-Yadain ka tariqa.",{})

-- ---------------- Computer & IT (from user's 500-batch) ----------------
addMCQ("ITN074","Computer & IT","DNS kis port par kaam karta hai?",{"Port 53","Port 80","Port 443","Port 21"},1,"TCP/UDP dono.",{})
addMCQ("ITN075","Computer & IT","Third Generation mein kis technology ka istamal hua?",{"Integrated Circuits","Transistors","Vacuum Tubes","Microprocessors"},1,"Computers chote aur tez hue.",{})
addMCQ("ITN076","Computer & IT","Excel mein #DIV/0! error ka matlab kya hai?",{"Number ko zero se divide kiya gaya","Text match nahi mila","Spelling galat","Memory khatam"},1,"Zero par division impossible.",{})
addMCQ("ITN077","Computer & IT","Phishing attack kis tarah ka hota hai?",{"Fake emails se credentials chori karna","Computer format karna","Internet khatam karna","Ads dikhana"},1,"Hackers asli company ban kar dhoka dete hain.",{})
addMCQ("ITN078","Computer & IT","IPv4 ki total length kitni hoti hai?",{"32 bits","128 bits","64 bits","16 bits"},1,"4 octets mein likhe jate hain.",{})
addMCQ("ITN079","Computer & IT","Python mein loop chalane ke liye kaun se keywords hain?",{"for aur while","loop aur repeat","do aur until","iterate"},1,"Looping ke liye use hote hain.",{})
addMCQ("ITN080","Computer & IT","Router ka main function kya hota hai?",{"Packet forwarding","Sirf wire connect","Printer chalana","Power control"},1,"Optimal route chunta hai.",{})
addMCQ("ITN081","Computer & IT","Blu-ray mein kis color ki laser use hoti hai?",{"Blue-Violet laser","Red laser","Infrared laser","Green laser"},1,"Shorter wavelength se zyadah storage.",{})
addMCQ("ITN082","Computer & IT","HTML mein text bold karne ke liye kaun sa tag hai?",{"b ya strong tag","bold tag","bd tag","bl tag"},1,"Text bold banane ke liye.",{})
addMCQ("ITN083","Computer & IT","DCL ki ahem misalein kya hain?",{"GRANT aur REVOKE","SELECT aur INSERT","CREATE aur DROP","UPDATE aur DELETE"},1,"Permissions control karti hain.",{})

-- ---------------- General Science (from user's 500-batch) ----------------
addMCQ("GSN075","General Science","WBCs ki kitni main categories hoti hain?",{"5 types","2 types","3 types","10 types"},1,"Immune system protect karti hain.",{})
addMCQ("GSN076","General Science","Wind direction maapne ke liye kaun sa instrument hota hai?",{"Wind Vane","Barometer","Hygrometer","Lactometer"},1,"Hawa ki simt ka pata chalta hai.",{})
addMCQ("GSN077","General Science","pH 7 se zyadah ho toh solution kaisa hota hai?",{"Basic Alkaline","Acidic","Neutral","Pure water"},1,"Soap ya bleach jaise.",{})
addMCQ("GSN078","General Science","Suraj ki roshni mein kaun si waves heat mehsoos karati hain?",{"Infrared Rays","Ultraviolet Rays","X-rays","Gamma rays"},1,"Dhoop mein garmahat mehsoos hoti hai.",{})
addMCQ("GSN079","General Science","Insani jism ki sab se bari gland kaunsi hai?",{"Liver","Thyroid","Pancreas","Pituitary"},1,"Sab se bara internal organ.",{})
addMCQ("GSN080","General Science","Heavy Water aam pani se kitna bhari hota hai?",{"10% zyadah","Doubna","Same","Adha"},1,"Deuterium ka mass double hota hai.",{})
addMCQ("GSN081","General Science","Sound waves ki speed sab se ziyada kis medium mein hoti hai?",{"Solids","Liquids","Gases","Vacuum"},1,"Particles qareeb hote hain.",{})
addMCQ("GSN082","General Science","Vitamin C ka chemical name kya hai?",{"Ascorbic Acid","Tocopherol","Retinol","Thiamine"},1,"Scurvy se bachata hai.",{})
addMCQ("GSN083","General Science","Adrenal Glands kahan waqie hoti hain?",{"Kidneys ke upar","Brain","Gale mein","Dil ke paas"},1,"Fight or flight response control karti hain.",{})
addMCQ("GSN084","General Science","Newton ka konsa law action reaction batata hai?",{"Third Law","First Law","Second Law","Law of Gravitation"},1,"Action aur reaction barabar hote hain.",{})

-- ---------------- History (from user's 500-batch) ----------------
addMCQ("HN024","History","Treaty of San Stefano (1878) kis jang ke nateje mein hui?",{"Russo-Turkish War","World War I","Crimean War","Opium War"},1,"Balkan region mein power dynamics badli.",{})

-- ---------------- World General Knowledge (from user's 500-batch) ----------------
addMCQ("WN062","World General Knowledge","Strait of Malacca kin do oceans ko milati hai?",{"Indian Ocean aur Pacific Ocean","Atlantic aur Pacific","Red Sea aur Arabian Sea","Mediterranean aur Atlantic"},1,"Asia ke liye international trade ke liye ahem.",{})
addMCQ("WN063","World General Knowledge","ILO ka headquarters kahan hai?",{"Geneva","Vienna","Paris","London"},1,"Mazdooron ke huqooq ke liye kaam karti hai.",{})

-- ---------------- History (from user's 500-batch) ----------------
addMCQ("HN025","History","Tehran Conference (1943) mein Big Three ne kis maqsad ke liye meeting ki?",{"Second Front kholne ke liye","UN banane ke liye","Japan surrender karwane","Trade"},1,"Iran ke Tehran mein hui.",{})

-- ---------------- World General Knowledge (from user's 500-batch) ----------------
addMCQ("WN064","World General Knowledge","Simpson Desert kis mulk mein hai?",{"Australia","Africa","South America","Central Asia"},1,"Red sand dunes ke liye mashhoor.",{})
addMCQ("WN065","World General Knowledge","NATO ka current headquarters kahan hai?",{"Brussels","Geneva","Paris","Berlin"},1,"Belgium ke capital mein hai.",{})
addMCQ("WN066","World General Knowledge","Bosporus Strait kis mulk mein hai?",{"Turkey","Egypt","Greece","Italy"},1,"Black Sea ko Sea of Marmara se milati hai.",{})
addMCQ("WN067","World General Knowledge","ICJ judges dunya ke kis system ke tehat chune jate hain?",{"UN quota system","Sirf US aur UK","Sirf Europe","Random"},1,"Global representation ke liye.",{})

-- ---------------- History (from user's 500-batch) ----------------
addMCQ("HN026","History","Battle of Borodino (1812) kis campaign ka hissa thi?",{"Napoleon ka Russia invasion","American Civil War","Franco-Prussian War","Seven Years War"},1,"Sab se khooni jang thi.",{})

-- ---------------- Constitution & Pak Affairs (from user's 500-batch) ----------------
addMCQ("CNN030","Constitution & Pak Affairs","1955 ki doosri Constituent Assembly ke Speaker kaun thay?",{"Abdul Wahab Khan","Maulvi Tamizuddin Khan","Fazlul Haq","H.S. Suhrawardy"},1,"Ch. Muhammad Ali ke daur mein.",{})
addMCQ("CNN031","Constitution & Pak Affairs","President ka resignation kis ko diya jata hai?",{"Speaker of NA","Prime Minister","Chief Justice","Senate"},1,"Governor President ko deta hai.",{})

-- ---------------- Pakistan Studies (from user's 500-batch) ----------------
addMCQ("PSN057","Pakistan Studies","Javid Nama kis ke naam se mansoob hai?",{"Bete Javid Iqbal ke naam se","Quaid-e-Azam","Rumi","King Amanullah"},1,"Aasmaanon ka safar bayan hai.",{})

-- ---------------- Constitution & Pak Affairs (from user's 500-batch) ----------------
addMCQ("CNN032","Constitution & Pak Affairs","CCI ki meetings saal mein kam az kam kitni baar honi chahiye?",{"Do baar","Aik baar","Har maah","3 saal mein aik baar"},1,"Rules ke mutabiq.",{})

-- ---------------- Pakistan Studies (from user's 500-batch) ----------------
addMCQ("PSN058","Pakistan Studies","Pehle Pakistani Commander-in-Chief of Navy kaun thay?",{"Vice Admiral H.M.S. Choudri","Admiral Asif Khawaja","Admiral Shahid Karim","Admiral Mansoorul Haq"},1,"1953 mein charge sambhala.",{})
addMCQ("PSN059","Pakistan Studies","Mangla Dam kis darya par hai?",{"River Jhelum","River Indus","River Chenab","River Kabul"},1,"Azad Kashmir Punjab border ke qareeb.",{})
addMCQ("PSN060","Pakistan Studies","Quaid-e-Azam ne 14 August 1947 ko pehli taqreer kahan ki?",{"Constituent Assembly Karachi","Minar-e-Pakistan Lahore","Delhi","Peshawar"},1,"Policy speech di thi.",{})
addMCQ("PSN061","Pakistan Studies","Basic Democracies system ka maqsad kya tha?",{"Local govt aur electoral college se intikhab","Sirf tax jama","Zameen taqseem","Trade"},1,"4-tier local government system.",{})
addMCQ("PSN062","Pakistan Studies","Pakistan ka sab se bara district population ke lihaz se kaunsa hai?",{"Lahore/Karachi","Faisalabad","Rawalpindi","Peshawar"},1,"Major urban districts.",{})
addMCQ("PSN063","Pakistan Studies","Liaquat-Nehru Pact ka mozu kya tha?",{"Minorities ke huqooq","Kashmir masla","Water distribution","Trade"},1,"Aqliyatoun ki security ke liye.",{})

-- ---------------- Islamiyat (from user's 500-batch) ----------------
addMCQ("ISLN086","Islamiyat","Kis Sahabi ko \"Khatib-ul-Islam\" ka laqab mila?",{"Hazrat Thabit bin Qais","Hazrat Hassan bin Thabit","Hazrat Abdullah bin Rawahah","Hazrat Ali"},1,"Aawaz buland aur khutbat moasar.",{})
addMCQ("ISLN087","Islamiyat","Surah Al-Waqiah ki tilawat ki kya fazilat hai?",{"Rizq ki tangi door karna","Bimari shifa","Hifazat","Dushman par fatah"},1,"Rat ko parhne se rizq mein barkat.",{})
addMCQ("ISLN088","Islamiyat","Jang-e-Hunain kis hijri mein aur kis ke khilaf thi?",{"8 Hijri Hawazin","6 Hijri","9 Hijri","10 Hijri"},1,"Fateh Makkah ke baad Hunain ki wadi.",{})
addMCQ("ISLN089","Islamiyat","Imam Ibn Majah kis ilaqa se tha?",{"Qazvin Iran","Bukhara","Nishapur","Madina"},1,"Kutub-e-Sittah ke muhaddiseen.",{})
addMCQ("ISLN090","Islamiyat","Police department ka formal nizam kis daur mein qayam hua?",{"Ali aur Uthman ke daur mein","Hazrat Abu Bakr","Hazrat Umar","Sab barabar"},1,"Law and order ke liye guard system.",{})
addMCQ("ISLN091","Islamiyat","Quran ki aakhri nazil hone wali aayat kaunsi mani jati hai?",{"Sood se mutaliq aayat","Surah Fatihah","Surah Ikhlas","Koi nahi"},1,"Mukhtalif qaul hain.",{})
addMCQ("ISLN092","Islamiyat","Quran mein Rukoo ki aam tadaad kitni hai?",{"540 Rukoo","300 Rukoo","1000 Rukoo","114 Rukoo"},1,"Tilawat ki division mein madad.",{})
addMCQ("ISLN093","Islamiyat","Sulah-e-Hudaibiyyah ka muhaida musalmanon ki taraf se kis ne likha?",{"Hazrat Ali bin Abi Talib","Hazrat Abu Bakr","Hazrat Uthman","Hazrat Zaid bin Sabit"},1,"Rasulullah ke hukm par.",{})
addMCQ("ISLN094","Islamiyat","Hazrat Dawood par kaunsi kitab nazil hui?",{"Zaboor","Taurat","Injeel","Quran"},1,"Zaboor Hazrat Dawood par nazil hui.",{})
addMCQ("ISLN095","Islamiyat","Late aane wala shakhs Namaz-e-Janaza mein kaise shamil hoga?",{"Imam ke sath shamil ho takbeerat poori kare","Dobara shuru kare","Namaz nahi hoti","Chorr de"},1,"Ruku sajdah nahi hota.",{})

-- ---------------- Computer & IT (from user's 500-batch) ----------------
addMCQ("ITN084","Computer & IT","DHCP ka network par kya kaam hota hai?",{"IP addresses assign karna","Websites load karna","Emails encrypt karna","Files compress karna"},1,"Naye devices ko IP deta hai.",{})
addMCQ("ITN085","Computer & IT","Second Generation mein transistors ne kis ki jagah li?",{"Vacuum tubes","Integrated Circuits","Microprocessors","Vacuum glass"},1,"Computers chote aur reliable huay.",{})
addMCQ("ITN086","Computer & IT","SUMIF() function ka kya istemal hota hai?",{"Condition ki base par sum","Sab numbers count","Maximum nikalna","Average nikalna"},1,"Specific criteria ki base par.",{})
addMCQ("ITN087","Computer & IT","Rootkit kis qisam ka malware hai?",{"Admin access deta khud chupata","Internet slow karta","Ads dikhata","Files delete karta"},1,"System ki deep layers mein baithta hai.",{})
addMCQ("ITN088","Computer & IT","IPv4 octet ki value kis range mein hoti hai?",{"0 se 255","1 se 100","-128 se 127","0 se 1024"},1,"Har 8-bit octet.",{})
addMCQ("ITN089","Computer & IT","Python dictionary kis bracket se banti hai?",{"Curly braces","Square brackets","Parentheses","Angle brackets"},1,"Key value pairs.",{})
addMCQ("ITN090","Computer & IT","Bridge ka kya kaam hota hai?",{"LAN segments connect karna","Speed double karna","Router banana","Power dena"},1,"Traffic filter karke networks jorta hai.",{})
addMCQ("ITN091","Computer & IT","DVD single-layer storage capacity kitni hoti hai?",{"4.7 GB","700 MB","25 GB","1.4 MB"},1,"CD se zyadah data store karti hai.",{})
addMCQ("ITN092","Computer & IT","HTML paragraph tag kya hai?",{"p tag","br tag","div tag","span tag"},1,"Paragraphs ke liye standard hai.",{})
addMCQ("ITN093","Computer & IT","TCL ki ahem misalein kya hain?",{"COMMIT aur ROLLBACK","SELECT INSERT","CREATE DROP","GRANT REVOKE"},1,"Transactions manage karti hain.",{})

-- ---------------- General Science (from user's 500-batch) ----------------
addMCQ("GSN085","General Science","Erythrocytes ka scientific naam kya hai?",{"Red Blood Cells","White Blood Cells","Platelets","Plasma cells"},1,"Oxygen transport karte hain.",{})
addMCQ("GSN086","General Science","Hydrometer kis cheez ko maapta hai?",{"Liquids ki density","Hawa ki nami","Hawa ka dabao","Zameen ki larzish"},1,"Relative density maapi jati hai.",{})
addMCQ("GSN087","General Science","pH 7 ho toh solution kaisa hota hai?",{"Neutral","Acidic","Basic","Toxic"},1,"7 neutral point hota hai.",{})
addMCQ("GSN088","General Science","Kaun si rays vitamin D banane ka sabab hain?",{"Ultraviolet Rays","Infrared rays","Micro waves","Radio waves"},1,"Skin mein vitamin D synthesis.",{})
addMCQ("GSN089","General Science","Taang tak jane wali sab se lambi nerve ka naam kya hai?",{"Sciatic Nerve","Vagus nerve","Optic nerve","Facial nerve"},1,"Lower back se pairon tak.",{})
addMCQ("GSN090","General Science","Heavy Water mein oxygen ka atom kaisa hota hai?",{"Same hota hai","Alag hota hai","Double heavy","Radioactive"},1,"Farq sirf hydrogen ki wajah se.",{})
addMCQ("GSN091","General Science","Sound intensity ki standard unit kya hoti hai?",{"Decibels","Hertz","Watts","Joules"},1,"Loudness decibels mein maapi jati hai.",{})
addMCQ("GSN092","General Science","Vitamin B1 ka chemical name kya hai?",{"Thiamine","Riboflavin","Niacin","Ascorbic Acid"},1,"Kami se Beriberi hota hai.",{})
addMCQ("GSN093","General Science","Pineal Gland kahan waqie hoti hai?",{"Brain ke andar","Gale mein","Jigar ke paas","Dil mein"},1,"Melatonin sleep cycle control karta hai.",{})
addMCQ("GSN094","General Science","F=ma kis Newton law se mutaliq hai?",{"Second Law","First Law","Third Law","Law of Gravitation"},1,"Force mass aur acceleration ka relationship.",{})

-- ---------------- History (from user's 500-batch) ----------------
addMCQ("HN027","History","Treaty of Versailles ke War Guilt Clause mein kis mulk ko zimmedar qarar diya gaya?",{"Germany","Austria-Hungary","Ottoman Empire","Bulgaria"},1,"Article 231 ke tehat.",{})

-- ---------------- World General Knowledge (from user's 500-batch) ----------------
addMCQ("WN068","World General Knowledge","Strait of Malacca Malaysia aur kis mulk ke darmiyan hai?",{"Indonesia","Thailand","Singapore","Philippines"},1,"Sumatra ke darmiyan waqie hai.",{})

-- ---------------- History (from user's 500-batch) ----------------
addMCQ("HN028","History","Yalta Conference mein UN ki buniyad par baat hui thi?",{"United Nations","League of Nations","EU","NATO"},1,"Churchill Roosevelt Stalin.",{})

-- ---------------- World General Knowledge (from user's 500-batch) ----------------
addMCQ("WN069","World General Knowledge","Sunan an-Nasa'i ke musannif ka asli naam kya tha?",{"Ahmad ibn Shu'ayb an-Nasa'i","Imam Bukhari","Imam Muslim","Imam Tirmidhi"},1,"Nasa Turkmenistan se nisbat.",{})
addMCQ("WN070","World General Knowledge","Quran mein kitni Makki aur Madani Surah hain (traditional)?",{"86 Makki 28 Madani","90 Makki 24 Madani","100 Makki 14 Madani","80 Makki 34 Madani"},1,"Total 114.",{})
addMCQ("WN071","World General Knowledge","Sahifay kis Nabi par nazil huay?",{"Hazrat Ibrahim","Hazrat Musa","Hazrat Isa","Hazrat Dawood"},1,"Suhuf-e-Ibrahim wa Musa.",{})

-- ---------------- Pakistan Studies (from user's 500-batch) ----------------
addMCQ("PSN064","Pakistan Studies","Sindh Chief Court ka faisla Federal Court mein kis ne palat diya?",{"Justice Muhammad Munir","Justice Cornelius","Justice Abdul Rashid","Justice Shahabuddin"},1,"Doctrine of Necessity.",{})

-- ---------------- Constitution & Pak Affairs (from user's 500-batch) ----------------
addMCQ("CNN033","Constitution & Pak Affairs","Senate mein har province se kitne members hote hain (Fata merger ke baad)?",{"23 members","10 members","15 members","30 members"},1,"Equal representation.",{})

-- ---------------- Pakistan Studies (from user's 500-batch) ----------------
addMCQ("PSN065","Pakistan Studies","Allama Iqbal ka mazar kahan hai?",{"Lahore","Sialkot","Islamabad","Karachi"},1,"Badshahi Masjid ke qareeb.",{})
addMCQ("PSN066","Pakistan Studies","Pehle Pakistani C-in-C Army kaun thay?",{"General Ayub Khan","General Musa Khan","General Tikka Khan","Field Marshal Ayub Khan"},1,"1951 mein bane.",{})
addMCQ("PSN067","Pakistan Studies","Tarbela Dam kab mukammal hua?",{"1976","1970","1980","1965"},1,"River Indus par.",{})
addMCQ("PSN068","Pakistan Studies","Lahore Resolution ki sadarat kis ne ki?",{"Quaid-e-Azam","Liaquat Ali Khan","Allama Iqbal","Fazl-ul-Haq"},1,"23 March 1940.",{})

-- ---------------- Constitution & Pak Affairs (from user's 500-batch) ----------------
addMCQ("CNN034","Constitution & Pak Affairs","1962 ka Ain kis ne mansookh kiya?",{"Yahya Khan","Ayub Khan","Zia-ul-Haq","Bhutto"},1,"25 March 1969.",{})

-- ---------------- Pakistan Studies (from user's 500-batch) ----------------
addMCQ("PSN069","Pakistan Studies","Simla Agreement par Indira Gandhi aur kis Pakistani leader ne dastakhat kiye?",{"Zulfikar Ali Bhutto","Ayub Khan","Yahya Khan","Liaquat Ali Khan"},1,"1972 mein.",{})

-- ---------------- Islamiyat (from user's 500-batch) ----------------
addMCQ("ISLN096","Islamiyat","Jang-e-Tabuk aakhri ghazwa tha, kis ke khilaf?",{"Roman Empire","Quraish","Jews of Khaibar","Banu Mustaliq"},1,"9 Hijri mein.",{})
addMCQ("ISLN097","Islamiyat","Quran ko standard mushaf mein kis Khalifa ne jama karwaya?",{"Hazrat Uthman","Hazrat Abu Bakr","Hazrat Umar","Hazrat Ali"},1,"Official standardization.",{})
addMCQ("ISLN098","Islamiyat","Namaz-e-Janaza mein kitni takbeerat hoti hain?",{"4","3","5","2"},1,"Ruku sajdah nahi.",{})
addMCQ("ISLN099","Islamiyat","Khulafa-e-Rashideen mein sab se chota dour kis ka tha?",{"Hazrat Abu Bakr","Hazrat Umar","Hazrat Uthman","Hazrat Ali"},1,"2 saal 3 maheenay.",{})
addMCQ("ISLN100","Islamiyat","Namaz-e-Istisqa kis maqsad ke liye hai?",{"Baarish ke liye","Solar eclipse","Khof ke waqt","Shukrana"},1,"Khushsali ke moqe par.",{})
addMCQ("ISLN101","Islamiyat","Sulah-e-Hudaibiyyah kis hijri mein hui?",{"6 Hijri","5 Hijri","7 Hijri","8 Hijri"},1,"Zulkadah 6 Hijri.",{})
addMCQ("ISLN102","Islamiyat","Kis Khalifa ke daur mein Iran Egypt mukammal fatah huay?",{"Hazrat Umar","Hazrat Abu Bakr","Hazrat Uthman","Hazrat Ali"},1,"Persian Byzantine empires.",{})
addMCQ("ISLN103","Islamiyat","Dar-e-Arqam kis maqsad ke liye tha?",{"Tableegh markaz","Wahi jagah","Hijrat mein chupna","Jang maidan"},1,"Musalman taleem lete thay.",{})

-- ---------------- Computer & IT (from user's 500-batch) ----------------
addMCQ("ITN094","Computer & IT","Cache memory ka maqsad kya hai?",{"CPU RAM speed gap kam karna","Storage barhana","Data save rakhna","Virus protect"},1,"Frequently used data.",{})
addMCQ("ITN095","Computer & IT","OSI model mein kitni layers hain?",{"7","6","5","8"},1,"Physical se Application tak.",{})
addMCQ("ITN096","Computer & IT","SQL Injection kis qisam ka attack hai?",{"Database vulnerability attack","Hardware damage","Packet sniffing","Password guessing"},1,"Malicious SQL execute karwata hai.",{})
addMCQ("ITN097","Computer & IT","MAC Address ki length kitni hai?",{"48 bits","32 bits","64 bits","128 bits"},1,"Unique physical address.",{})
addMCQ("ITN098","Computer & IT","Python kis ne ijad ki?",{"Guido van Rossum","Dennis Ritchie","James Gosling","Bjarne Stroustrup"},1,"1991 mein launch.",{})
addMCQ("ITN099","Computer & IT","Cookies ka maqsad kya hai?",{"Browsing preferences yaad rakhna","Virus se bachana","Speed tezz karna","Disk clean karna"},1,"Session data save karti hain.",{})
addMCQ("ITN100","Computer & IT","WWW ki ijad kis ne ki?",{"Tim Berners-Lee","Bill Gates","Steve Jobs","Mark Zuckerberg"},1,"1989 CERN mein.",{})
addMCQ("ITN101","Computer & IT","2nd Generation mein transistors ne kis ki jagah li?",{"Vacuum Tubes","ICs","Microprocessors","Quantum Chips"},1,"1956-1965.",{})

-- ---------------- General Science (from user's 500-batch) ----------------
addMCQ("GSN095","General Science","Suraj ki roshni zameen tak pohnchne mein kitna waqt leti hai?",{"8 minutes 20 seconds","4 minutes 30 seconds","12 minutes","15 minutes"},1,"500 seconds ke qareeb.",{})
addMCQ("GSN096","General Science","Scurvy kis vitamin ki kami se hoti hai?",{"Vitamin C","Vitamin A","Vitamin B","Vitamin D"},1,"Ascorbic Acid ki kami.",{})
addMCQ("GSN097","General Science","Heavy Water ka chemical formula kya hai?",{"D2O","H2O","H2O2","D3O"},1,"Deuterium Oxide.",{})
addMCQ("GSN098","General Science","Atmosphere mein sab se zyada kaunsi gas hai?",{"Nitrogen","Oxygen","Hydrogen","Carbon Dioxide"},1,"Qareeban 78%.",{})
addMCQ("GSN099","General Science","Bauxite kis metal ka ore hai?",{"Aluminium","Iron","Copper","Gold"},1,"Chemical process se alag.",{})
addMCQ("GSN100","General Science","Earth ke core mein sab se ziyada element kaunsa hai?",{"Iron aur Nickel","Silicon Oxygen","Gold Silver","Hydrogen Helium"},1,"NIFE bhi kehte hain.",{})

-- ============================================================
-- NEW ADDED MCQs (unique "EXT" ID prefix, verified against the
-- whole DB for duplicates, each with several related MCQs from
-- the same mini-set so "SHOW ALL RELATED" is always useful)
-- ============================================================
-- ---------------- Pakistan Studies ----------------
addMCQ("EXT001","Pakistan Studies","Pakistan ka jhanda sab se pehle kab lehraya gaya?",{"14 August 1947","23 March 1940","11 September 1948","6 September 1965"},1,"Azadi ke din official taur par lehraya gaya.",{"EXT002","EXT003"})
addMCQ("EXT002","Pakistan Studies","Pakistan ke jhande mein safed patti kis cheez ki alamat hai?",{"Aqliyaton ka","Fauj ka","Zamin ka","Samandar ka"},1,"Aqliyaton (minorities) ki namaindagi karti hai.",{"EXT001","EXT003"})
addMCQ("EXT003","Pakistan Studies","Pakistan ka qaumi phool kaunsa hai?",{"Jasmine (Chambeli)","Rose","Tulip","Lily"},1,"Chambeli ko qaumi phool ka darja hasil hai.",{"EXT001","EXT002","EXT004"})
addMCQ("EXT004","Pakistan Studies","Pakistan ka qaumi janwar kaunsa hai?",{"Markhor","Sherni","Deer","Bakri"},1,"Markhor pahaadi ilaqon mein paya jata hai.",{"EXT003","EXT005"})
addMCQ("EXT005","Pakistan Studies","Pakistan ka qaumi parinda kaunsa hai?",{"Chukar (Titar)","Kabootar","Mor","Baaz"},1,"Chukar Partridge Pakistan ka qaumi parinda hai.",{"EXT004","EXT003"})

-- ---------------- Islamiyat ----------------
addMCQ("EXT010","Islamiyat","Quran-e-Pak ki sab se choti Surah kaunsi hai?",{"Al-Kausar","Al-Ikhlas","An-Nas","Al-Asr"},1,"Sirf 3 ayat par mushtamil hai.",{"EXT011","EXT012"})
addMCQ("EXT011","Islamiyat","Quran-e-Pak ki sab se bari Surah kaunsi hai?",{"Al-Baqarah","Aal-e-Imran","An-Nisa","Al-Maidah"},1,"286 ayat par mushtamil hai.",{"EXT010","EXT013"})
addMCQ("EXT012","Islamiyat","Islam ka teesra rukn kya hai?",{"Roza","Namaz","Zakat","Hajj"},1,"Ramzan ke mahine mein farz hai.",{"EXT010","EXT013"})
addMCQ("EXT013","Islamiyat","Khulafa-e-Rashideen mein sab se pehle khalifa kaun the?",{"Hazrat Abu Bakr Siddiq (RA)","Hazrat Umar (RA)","Hazrat Usman (RA)","Hazrat Ali (RA)"},1,"Pehle khalifa the.",{"EXT011","EXT012","EXT014"})
addMCQ("EXT014","Islamiyat","Khulafa-e-Rashideen mein aakhri khalifa kaun the?",{"Hazrat Ali (RA)","Hazrat Umar (RA)","Hazrat Usman (RA)","Hazrat Abu Bakr (RA)"},1,"Chautha aur aakhri khalifa the.",{"EXT013"})

-- ---------------- General Science ----------------
addMCQ("EXT020","General Science","Insani jism mein sab se choti haddi kahan hoti hai?",{"Kaan (Stapes)","Haath","Paon","Rerh ki haddi"},1,"Kaan mein Stapes naam ki haddi sab se choti hoti hai.",{"EXT021","EXT022"})
addMCQ("EXT021","General Science","Insani jism mein sab se lambi haddi kaunsi hai?",{"Femur (Jaanghd)","Humerus","Tibia","Radius"},1,"Jaangh mein hoti hai.",{"EXT020","EXT023"})
addMCQ("EXT022","General Science","Photosynthesis mein paudhe kaunsi gas khaarij karte hain?",{"Oxygen","Carbon Dioxide","Nitrogen","Hydrogen"},1,"Sunlight ki madad se O2 banate hain.",{"EXT020","EXT023"})
addMCQ("EXT023","General Science","Insani jism ka sab se bada organ kaunsa hai?",{"Jild (Skin)","Jigar","Dil","Guray"},1,"Poore jism ko cover karti hai.",{"EXT021","EXT022"})

-- ---------------- Everyday Science ----------------
addMCQ("EXT030","Everyday Science","Fridge mein thandak paida karne wali gas ko kya kehte hain?",{"Refrigerant","Oxygen","Nitrogen","Methane"},1,"Compression-expansion cycle se garmi absorb karti hai.",{"EXT031"})
addMCQ("EXT031","Everyday Science","LED ka poora naam kya hai?",{"Light Emitting Diode","Low Energy Device","Light Electric Diode","Liquid Emitting Diode"},1,"Kam bijli mein zyada roshni deta hai.",{"EXT030","EXT032"})
addMCQ("EXT032","Everyday Science","Barometer kis cheez ko measure karta hai?",{"Air Pressure","Temperature","Humidity","Speed"},1,"Mausam ka andaza lagane mein madad karta hai.",{"EXT030","EXT031"})

-- ---------------- English ----------------
addMCQ("EXT040","English","'Happy' ka antonym kya hai?",{"Sad","Joyful","Glad","Cheerful"},1,"Opposite meaning wala lafz.",{"EXT041"})
addMCQ("EXT041","English","'Big' ka synonym kya hai?",{"Large","Small","Tiny","Short"},1,"Same meaning wala lafz.",{"EXT040","EXT042"})
addMCQ("EXT042","English","Is jumle mein verb pehchanein: 'She runs every morning.'",{"runs","she","every","morning"},1,"'Runs' action/verb hai.",{"EXT040","EXT041"})

-- ---------------- Computer & IT ----------------
addMCQ("EXT050","Computer & IT","CPU ka poora naam kya hai?",{"Central Processing Unit","Computer Personal Unit","Central Program Unit","Central Processing Utility"},1,"Computer ka 'dimagh' kehlata hai.",{"EXT051"})
addMCQ("EXT051","Computer & IT","RAM ka poora naam kya hai?",{"Random Access Memory","Read Access Memory","Rapid Access Memory","Real Access Memory"},1,"Temporary data store karti hai.",{"EXT050","EXT052"})
addMCQ("EXT052","Computer & IT","HTML kis cheez ke liye use hoti hai?",{"Web pages banane ke liye","Database ke liye","Networking ke liye","Antivirus ke liye"},1,"HyperText Markup Language.",{"EXT050","EXT051"})

-- ---------------- Geography ----------------
addMCQ("EXT060","Geography","Duniya ka sab se bada sehra kaunsa hai?",{"Sahara Desert","Thar Desert","Gobi Desert","Kalahari Desert"},1,"Africa mein waqai hai.",{"EXT061"})
addMCQ("EXT061","Geography","Duniya ka sab se lamba darya kaunsa hai?",{"Nile River","Amazon River","Indus River","Yangtze River"},1,"Africa mein behta hai.",{"EXT060","EXT062"})
addMCQ("EXT062","Geography","Duniya ka sab se bada mahasagar (ocean) kaunsa hai?",{"Pacific Ocean","Atlantic Ocean","Indian Ocean","Arctic Ocean"},1,"Rakbe ke lihaz se sab se bada hai.",{"EXT060","EXT061"})

-- ---------------- Constitution & Pak Affairs ----------------
addMCQ("EXT070","Constitution & Pak Affairs","Pakistan ki Senate mein kul kitni seats hain?",{"96","100","104","110"},1,"Upper house of Parliament.",{"EXT071"})
addMCQ("EXT071","Constitution & Pak Affairs","Pakistan ka Chief Executive kaun hota hai?",{"Prime Minister","President","Chief Justice","Speaker"},1,"Hakumat ka nizam chalata hai.",{"EXT070"})

-- ---------------- World General Knowledge ----------------
addMCQ("EXT080","World General Knowledge","United Nations ka headquarter kahan hai?",{"New York","Geneva","Paris","London"},1,"UN ka markazi daftar.",{"EXT081"})
addMCQ("EXT081","World General Knowledge","WHO ka poora naam kya hai?",{"World Health Organization","World Human Organization","World Health Office","World Humanity Organization"},1,"Sehat se mutaliq idara.",{"EXT080"})

-- ---------------- Sports ----------------
addMCQ("EXT090","Sports","Cricket match mein ek over mein kitni balls hoti hain?",{"6","5","8","10"},1,"Standard over mein 6 balls hoti hain.",{"EXT091"})
addMCQ("EXT091","Sports","Football match mein ek team mein kitne players hote hain?",{"11","10","12","9"},1,"Field par 11 khilari hote hain.",{"EXT090"})

-- ---------------- History ----------------
addMCQ("EXT100","History","Second World War kis saal khatam hui?",{"1945","1939","1944","1950"},1,"Japan ke surrender ke baad khatam hui.",{"EXT101"})
addMCQ("EXT101","History","Second World War kis saal shuru hui?",{"1939","1945","1935","1941"},1,"Poland par hamle se shuru hui.",{"EXT100"})

-- ---------------- Current Affairs (Verified) ----------------
addMCQ("EXT110","Current Affairs (Verified)","G20 mein kitne mulk shamil hain?",{"19 mulk + EU + African Union","10","25","15"},1,"Bade maashi mulkon ka forum hai. (Tarikh check karte rahein kyunke membership update hoti rehti hai.)",{"EXT111"})
addMCQ("EXT111","Current Affairs (Verified)","SAARC ka poora naam kya hai?",{"South Asian Association for Regional Cooperation","South Asian Alliance","South Africa Regional Cooperation","South Asian Aid Council"},1,"Junoobi Asia ke mulkon ki tanzeem.",{"EXT110"})

-- ============================================================
-- LOAD LOCAL EXPANSION FILES (batch .lua files dropped in folder)
-- ============================================================
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
            local exists=false
            for _,m in ipairs(MCQ_DB) do if m.id==item.id then exists=true break end end
            if not exists then
              table.insert(MCQ_DB,item)
              local found=false
              for _,c in ipairs(CATEGORIES) do if c==item.category then found=true end end
              if not found then table.insert(CATEGORIES,item.category) end
            end
          end
        end
      end
    end
    p:close()
  end)
end
loadExpansionFiles()

-- ============================================================
-- LOAD USER-ADDED MCQs (permanent, separate small file — always loaded,
-- and travels with the plugin if BOTH files are shared together)
-- ============================================================
local USER_MCQ_FILE="/sdcard/Jieshuo/mcq_data/user_added.lua"
local function loadUserAddedMCQs()
  pcall(function()
    local ok,data=pcall(dofile,USER_MCQ_FILE)
    if ok and type(data)=="table" then
      for _,item in ipairs(data) do
        local exists=false
        for _,m in ipairs(MCQ_DB) do if m.id==item.id then exists=true break end end
        if not exists then
          table.insert(MCQ_DB,item)
          local found=false
          for _,c in ipairs(CATEGORIES) do if c==item.category then found=true end end
          if not found then table.insert(CATEGORIES,item.category) end
        end
      end
    end
  end)
end
loadUserAddedMCQs()

-- ============================================================
-- DEDUPE SAFETY NET — ensures no MCQ (core, expansion file,
-- user-added, or online-synced) ever appears twice. Compares
-- normalized question text; first occurrence wins, later exact
-- repeats are silently dropped.
-- ============================================================
local function dedupeQuestions()
  local seen={}
  local out={}
  for _,m in ipairs(MCQ_DB) do
    local key=m.question:lower():gsub("%s+","")
    if not seen[key] then
      seen[key]=true
      table.insert(out,m)
    end
  end
  MCQ_DB=out
end
dedupeQuestions()

-- ============================================================
-- SAVE A NEW USER-ADDED MCQ PERMANENTLY
-- Reads the whole user_added.lua file, appends the new entry as a
-- proper Lua table, rewrites the file. This makes it permanent:
-- it survives app/plugin restarts, and if you copy BOTH the plugin's
-- .lua file AND this mcq_data folder to someone else's phone,
-- your added MCQs go with it.
-- ============================================================
local function ensureDirExists(path)
  pcall(function() os.execute('mkdir -p "'..path..'"') end)
end

local function readAllUserMCQs()
  local ok,data=pcall(dofile,USER_MCQ_FILE)
  if ok and type(data)=="table" then return data end
  return {}
end

local function writeAllUserMCQs(list)
  ensureDirExists(EXPANSION_DIR)
  local f=io.open(USER_MCQ_FILE,"w")
  if not f then return false end
  f:write("-- Auto-generated by MY MCQ TRAINER. Do not edit manually unless you know Lua.\n")
  f:write("return {\n")
  for _,m in ipairs(list) do
    f:write('{id="'..m.id..'",category="'..m.category:gsub('"','\\"')..'",question="'..m.question:gsub('"','\\"')..
      '",options={"'..m.options[1]:gsub('"','\\"')..'","'..m.options[2]:gsub('"','\\"')..'","'..
      m.options[3]:gsub('"','\\"')..'","'..m.options[4]:gsub('"','\\"')..'"},correct='..m.correct..
      ',description="'..(m.description or ""):gsub('"','\\"')..'",related={}},\n')
  end
  f:write("}\n")
  f:close()
  return true
end

-- ============================================================
-- EDIT OVERRIDES (persists edits/renames made to ANY MCQ — core,
-- expansion-file, or user-added — via long-press EDIT/RENAME.
-- Stored separately so the huge core database above never needs
-- to be rewritten; on every load we re-apply saved overrides on
-- top of whatever MCQ_DB already has.)
-- ============================================================
local OVERRIDE_FILE=EXPANSION_DIR.."edited_overrides.lua"
local function readAllOverrides()
  local ok,data=pcall(dofile,OVERRIDE_FILE)
  if ok and type(data)=="table" then return data end
  return {}
end
local function writeAllOverrides(list)
  ensureDirExists(EXPANSION_DIR)
  local f=io.open(OVERRIDE_FILE,"w")
  if not f then return false end
  f:write("-- Auto-generated by MY MCQ TRAINER (edit/rename history). Do not edit manually.\n")
  f:write("return {\n")
  for _,m in ipairs(list) do
    f:write('{id="'..m.id..'",category="'..m.category:gsub('"','\\"')..'",question="'..m.question:gsub('"','\\"')..
      '",options={"'..m.options[1]:gsub('"','\\"')..'","'..m.options[2]:gsub('"','\\"')..'","'..
      m.options[3]:gsub('"','\\"')..'","'..m.options[4]:gsub('"','\\"')..'"},correct='..m.correct..
      ',description="'..(m.description or ""):gsub('"','\\"')..'"},\n')
  end
  f:write("}\n")
  f:close()
  return true
end
local function applyOverrides()
  local overrides=readAllOverrides()
  for _,o in ipairs(overrides) do
    local target=findById(o.id)
    if target then
      target.category=o.category; target.question=o.question; target.options=o.options
      target.correct=o.correct; target.description=o.description
      local found=false
      for _,c in ipairs(CATEGORIES) do if c==target.category then found=true end end
      if not found then table.insert(CATEGORIES,target.category) end
    end
  end
end
-- saves (or updates) one MCQ's override permanently
function saveMcqOverride(m)
  local all=readAllOverrides()
  local replaced=false
  for i,o in ipairs(all) do
    if o.id==m.id then all[i]={id=m.id,category=m.category,question=m.question,options=m.options,correct=m.correct,description=m.description}; replaced=true; break end
  end
  if not replaced then table.insert(all,{id=m.id,category=m.category,question=m.question,options=m.options,correct=m.correct,description=m.description}) end
  return writeAllOverrides(all)
end

-- ============================================================
-- AUTO CATEGORY DETECTION (keyword scoring against CATEGORIES)
-- ============================================================
local CATEGORY_KEYWORDS={
  ["Pakistan Studies"]={"pakistan","quaid","jinnah","liaquat","lahore resolution","two-nation","1947","1971","allama iqbal","muslim league"},
  ["Islamiyat"]={"quran","surah","hazrat","hijri","namaz","roza","zakat","hajj","ghazwa","sahabi","islam","nabi","khalifa"},
  ["General Science"]={"jism","chromosome","organ","gas","photosynthesis","haddiyan","atom","dna","planet","sayyara","science"},
  ["Everyday Science"]={"thermometer","barometer","bijli","waves","led","refrigerator","solar","x-ray","microwave"},
  ["English"]={"synonym","antonym","verb","noun","adjective","tense","grammar","sentence","adverb"},
  ["Computer & IT"]={"computer","cpu","ram","internet","html","url","software","database","sql","network","ip address"},
  ["Geography"]={"darya","sehra","pahaar","continent","river","desert","mountain","ocean","shehar","capital"},
  ["Constitution & Pak Affairs"]={"ain","constitution","article","amendment","assembly","senate","president","governor"},
  ["World General Knowledge"]={"united nations","un ","who","nasa","currency","mulk","world"},
  ["Sports"]={"cricket","football","hockey","olympic","match","world cup","tennis","team"},
  ["History"]={"war","empire","jang","mughal","battle","century","treaty","revolution"},
  ["Current Affairs (Verified)"]={"saarc","g20","brics","cpec","current","2024","2025","2026","president","prime minister"}
}

function detectCategory(questionText)
  local q=questionText:lower()
  local bestCat,bestScore="Current Affairs (Verified)",0
  for cat,kws in pairs(CATEGORY_KEYWORDS) do
    local score=0
    for _,kw in ipairs(kws) do
      if q:find(kw,1,true) then score=score+1 end
    end
    if score>bestScore then bestScore=score; bestCat=cat end
  end
  return bestCat
end

-- ============================================================
-- HELPERS
-- ============================================================
function findById(id) for _,m in ipairs(MCQ_DB) do if m.id==id then return m end end return nil end
function getByCategory(cat) local l={} for _,m in ipairs(MCQ_DB) do if m.category==cat then table.insert(l,m) end end return l end
function searchMCQ(kw) local l={} kw=kw:lower() for _,m in ipairs(MCQ_DB) do if m.question:lower():find(kw,1,true) then table.insert(l,m) end end return l end

-- apply any saved edits/renames now that findById exists and the
-- full MCQ_DB (core + expansion files + user-added) has loaded
applyOverrides()

local bookmarks={}

-- ============================================================
-- UI: MCQ LIST WITH LONG-PRESS ACTIONS (tap = open, long-press =
-- Edit / Rename / Share / Copy / Bookmark menu). Used everywhere
-- a list of MCQs is shown: category browse, search, bookmarks,
-- related-questions.
-- ============================================================
function showMcqActionMenu(m)
  local options={"OPEN / READ","EDIT MCQ","RENAME (Change Category)","SHARE","COPY TEXT","ADD TO BOOKMARKS"}
  ssd(AlertDialog.Builder(context).setTitle(m.id.." - Actions").setItems(options,sc(function(dlg,which)
    if which==0 then showQuestionDetail(m)
    elseif which==1 then showEditMCQ(m)
    elseif which==2 then showRenameMCQCategory(m)
    elseif which==3 then shareMcqText(m)
    elseif which==4 then copyMcqText(m)
    elseif which==5 then
      bookmarks[m.id]=m
      ssd(AlertDialog.Builder(context).setTitle("Saved").setMessage("Bookmark ho gaya.").setPositiveButton("OK",nil))
    end
  end)).setNegativeButton("CANCEL",nil))
end

function showMcqListDialog(title,mcqList)
  if #mcqList==0 then
    ssd(AlertDialog.Builder(context).setTitle("Empty").setMessage("Is list mein abhi koi MCQ nahi.").setPositiveButton("OK",nil))
    return
  end
  local titles={}
  for _,m in ipairs(mcqList) do table.insert(titles,m.id..": "..m.question) end
  local lv=ListView(context)
  local simpleListItemLayout=17039370 -- android.R.layout.simple_list_item_1
  pcall(function() simpleListItemLayout=luajava.bindClass("android.R$layout").simple_list_item_1 end)
  local adapter=ArrayAdapter(context,simpleListItemLayout,titles)
  lv.setAdapter(adapter)
  lv.setOnItemClickListener(AdapterView.OnItemClickListener({onItemClick=sc(function(parent,view,position,id)
    showQuestionDetail(mcqList[position+1])
  end)}))
  lv.setOnItemLongClickListener(AdapterView.OnItemLongClickListener({onItemLongClick=function(parent,view,position,id)
    local ok=pcall(function() showMcqActionMenu(mcqList[position+1]) end)
    return true
  end}))
  ssd(AlertDialog.Builder(context).setTitle(title.." (long-press = more actions)").setView(lv).setNegativeButton("BACK",nil))
end

-- ============================================================
-- UI: question detail
-- ============================================================
function showQuestionDetail(m)
  local labels={"A","B","C","D"}
  local optionsText=""
  for i,opt in ipairs(m.options) do optionsText=optionsText..labels[i]..") "..opt.."\n" end
  local fullText=m.question.."\n\n"..optionsText.."\nCorrect Answer: "..labels[m.correct]..") "..m.options[m.correct].."\n\nExplanation: "..m.description
  local d=AlertDialog.Builder(context).setTitle(m.category.." - "..m.id).setMessage(fullText)
  d.setPositiveButton("READ ALOUD",sc(function() speakMcq(fullText) end))
  d.setNeutralButton("SHOW ALL RELATED",sc(function()
    if m.related and #m.related>0 then
      local relList={}
      for _,rid in ipairs(m.related) do
        local rm=findById(rid)
        if rm then table.insert(relList,rm) end
      end
      if #relList>0 then
        showMcqListDialog("Related MCQs ("..#relList..")",relList)
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
  speakMcq(buildSpokenQuestion(m))
end

function browseCategory(cat)
  local mcqs=getByCategory(cat)
  showMcqListDialog(cat.." - Total: "..#mcqs.." MCQs",mcqs)
end

-- ============================================================
-- QUIZ PLATFORM
-- ============================================================
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
  speakMcq(buildSpokenQuestion(m))
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
  ssd(AlertDialog.Builder(context).setTitle(cat.." - Total: "..cnt.." MCQs").setItems({"BROWSE ALL MCQs (Line by Line)","START QUIZ"},sc(function(dlg,which)
    if which==0 then browseCategory(cat) else startQuiz(cat) end
  end)).setNegativeButton("BACK",nil))
end

-- generic category picker used by the CHOOSE CATEGORY and PLAY QUIZ
-- top-level buttons; cb(categoryName) runs once the user taps one
function pickCategory(promptTitle,cb)
  local catLabels={}
  for _,c in ipairs(CATEGORIES) do
    local cnt=#getByCategory(c)
    table.insert(catLabels,c.." ("..cnt.." MCQs)")
  end
  ssd(AlertDialog.Builder(context).setTitle(promptTitle.." - Grand Total: "..#MCQ_DB).setItems(catLabels,sc(function(dlg,which) cb(CATEGORIES[which+1]) end)).setNegativeButton("BACK",nil))
end

function showSearch()
  local et=EditText(context); et.setHint("Type keyword...")
  local d=AlertDialog.Builder(context).setTitle("Search MCQs").setView(et)
  d.setPositiveButton("SEARCH",sc(function()
    local kw=tostring(et.getText()):gsub("^%s+",""):gsub("%s+$","")
    local results=searchMCQ(kw)
    if #results==0 then ssd(AlertDialog.Builder(context).setTitle("No Results").setMessage("Koi MCQ nahi mila.").setPositiveButton("OK",nil)); return end
    showMcqListDialog("Results ("..#results..")",results)
  end))
  d.setNegativeButton("CANCEL",nil)
  ssd(d)
end

function showBookmarks()
  local list={}
  for id,m in pairs(bookmarks) do table.insert(list,m) end
  showMcqListDialog("Bookmarks ("..#list..")",list)
end

-- ============================================================
-- ADD MCQ SCREEN (real, permanent, auto-category)
-- ============================================================
function showAddMCQ()
  local layout=LinearLayout(context); layout.setOrientation(1); layout.setPadding(20,20,20,20)
  local sv=ScrollView(context); sv.addView(layout)

  local qLabel=TextView(context); qLabel.setText("Question:"); layout.addView(qLabel)
  local qEdit=EditText(context); qEdit.setHint("Apna sawal yahan likhein..."); qEdit.setMinLines(2); layout.addView(qEdit)

  local labels={"Option A:","Option B:","Option C:","Option D:"}
  local optEdits={}
  for i=1,4 do
    local l=TextView(context); l.setText(labels[i]); l.setPadding(0,10,0,0); layout.addView(l)
    local e=EditText(context); layout.addView(e)
    optEdits[i]=e
  end

  local corLabel=TextView(context); corLabel.setText("Sahi Jawab (A, B, C, ya D):"); corLabel.setPadding(0,10,0,0); layout.addView(corLabel)
  local corEdit=EditText(context); corEdit.setHint("A"); layout.addView(corEdit)

  local descLabel=TextView(context); descLabel.setText("Explanation (optional):"); descLabel.setPadding(0,10,0,0); layout.addView(descLabel)
  local descEdit=EditText(context); descEdit.setMinLines(2); layout.addView(descEdit)

  local catLabel=TextView(context); catLabel.setText("Category (khaali chorein = khud detect hogi):"); catLabel.setPadding(0,10,0,0); layout.addView(catLabel)
  local catEdit=EditText(context); catEdit.setHint("Khaali chor dein for auto-detect"); layout.addView(catEdit)

  local statusTxt=TextView(context); statusTxt.setPadding(0,10,0,0); layout.addView(statusTxt)

  local addBtn=Button(context); addBtn.setText("SAVE MCQ PERMANENTLY"); layout.addView(addBtn)

  addBtn.onClick=sc(function()
    local q=tostring(qEdit.getText()):gsub("^%s+",""):gsub("%s+$","")
    local opts={}
    for i=1,4 do opts[i]=tostring(optEdits[i].getText()):gsub("^%s+",""):gsub("%s+$","") end
    local corLetter=tostring(corEdit.getText()):gsub("^%s+",""):gsub("%s+$",""):upper()
    local corMap={A=1,B=2,C=3,D=4}
    local correct=corMap[corLetter]
    local desc=tostring(descEdit.getText()):gsub("^%s+",""):gsub("%s+$","")
    if desc=="" then desc="Explanation not provided." end
    local catInput=tostring(catEdit.getText()):gsub("^%s+",""):gsub("%s+$","")

    if q=="" or opts[1]=="" or opts[2]=="" or opts[3]=="" or opts[4]=="" then
      statusTxt.setText("Please fill question and all 4 options.")
      return
    end
    if not correct then
      statusTxt.setText("Please enter A, B, C, or D for correct answer.")
      return
    end

    local qKey=q:lower():gsub("%s+","")
    for _,existing in ipairs(MCQ_DB) do
      if existing.question:lower():gsub("%s+","")==qKey then
        statusTxt.setText("Ye MCQ pehle se database mein maujood hai (ID: "..existing.id.."). Duplicate add nahi hoga.")
        return
      end
    end

    local category=catInput
    if category=="" then category=detectCategory(q) end

    local catFound=false
    for _,c in ipairs(CATEGORIES) do if c==category then catFound=true end end
    if not catFound then table.insert(CATEGORIES,category) end

    local newId="USR"..os.time()..math.random(100,999)
    local newMcq={id=newId,category=category,question=q,options=opts,correct=correct,description=desc,related={}}

    table.insert(MCQ_DB,newMcq)

    local allUser=readAllUserMCQs()
    table.insert(allUser,newMcq)
    local saved=writeAllUserMCQs(allUser)

    if saved then
      statusTxt.setText("Saved! Category: "..category.."\nID: "..newId.."\nTotal MCQs now: "..#MCQ_DB)
      speakMcq("MCQ saved in category "..category)
      qEdit.setText(""); for i=1,4 do optEdits[i].setText("") end; corEdit.setText(""); descEdit.setText(""); catEdit.setText("")
    else
      statusTxt.setText("Saved for this session, but permanent save to file failed. Check storage permission.")
    end
  end)

  ssd(AlertDialog.Builder(context).setTitle("ADD NEW MCQ").setView(sv).setPositiveButton("CLOSE",nil))
end

-- ============================================================
-- EDIT MCQ (works on ANY MCQ — core, expansion, or user-added.
-- Change is applied in-memory immediately and saved permanently
-- via saveMcqOverride, reached from long-press -> EDIT MCQ)
-- ============================================================
function showEditMCQ(m)
  local layout=LinearLayout(context); layout.setOrientation(1); layout.setPadding(20,20,20,20)
  local sv=ScrollView(context); sv.addView(layout)

  local idTxt=TextView(context); idTxt.setText("Editing: "..m.id.." ("..m.category..")"); idTxt.setTextSize(13); layout.addView(idTxt)

  local qLabel=TextView(context); qLabel.setText("Question:"); qLabel.setPadding(0,10,0,0); layout.addView(qLabel)
  local qEdit=EditText(context); qEdit.setMinLines(2); qEdit.setText(m.question); layout.addView(qEdit)

  local labels={"Option A:","Option B:","Option C:","Option D:"}
  local optEdits={}
  for i=1,4 do
    local l=TextView(context); l.setText(labels[i]); l.setPadding(0,10,0,0); layout.addView(l)
    local e=EditText(context); e.setText(m.options[i]); layout.addView(e)
    optEdits[i]=e
  end

  local corLabel=TextView(context); corLabel.setText("Sahi Jawab (A, B, C, ya D):"); corLabel.setPadding(0,10,0,0); layout.addView(corLabel)
  local ansLetters={"A","B","C","D"}
  local corEdit=EditText(context); corEdit.setText(ansLetters[m.correct] or "A"); layout.addView(corEdit)

  local descLabel=TextView(context); descLabel.setText("Explanation:"); descLabel.setPadding(0,10,0,0); layout.addView(descLabel)
  local descEdit=EditText(context); descEdit.setMinLines(2); descEdit.setText(m.description); layout.addView(descEdit)

  local catLabel=TextView(context); catLabel.setText("Category:"); catLabel.setPadding(0,10,0,0); layout.addView(catLabel)
  local catEdit=EditText(context); catEdit.setText(m.category); layout.addView(catEdit)

  local statusTxt=TextView(context); statusTxt.setPadding(0,10,0,0); layout.addView(statusTxt)

  local saveBtn=Button(context); saveBtn.setText("SAVE CHANGES PERMANENTLY"); layout.addView(saveBtn)

  saveBtn.onClick=sc(function()
    local q=tostring(qEdit.getText()):gsub("^%s+",""):gsub("%s+$","")
    local opts={}
    for i=1,4 do opts[i]=tostring(optEdits[i].getText()):gsub("^%s+",""):gsub("%s+$","") end
    local corLetter=tostring(corEdit.getText()):gsub("^%s+",""):gsub("%s+$",""):upper()
    local corMap={A=1,B=2,C=3,D=4}
    local correct=corMap[corLetter]
    local desc=tostring(descEdit.getText()):gsub("^%s+",""):gsub("%s+$","")
    if desc=="" then desc="Explanation not provided." end
    local category=tostring(catEdit.getText()):gsub("^%s+",""):gsub("%s+$","")
    if category=="" then category=m.category end

    if q=="" or opts[1]=="" or opts[2]=="" or opts[3]=="" or opts[4]=="" then
      statusTxt.setText("Please fill question and all 4 options.")
      return
    end
    if not correct then
      statusTxt.setText("Please enter A, B, C, or D for correct answer.")
      return
    end

    m.question=q; m.options=opts; m.correct=correct; m.description=desc; m.category=category
    local found=false
    for _,c in ipairs(CATEGORIES) do if c==category then found=true end end
    if not found then table.insert(CATEGORIES,category) end

    local saved=saveMcqOverride(m)
    if saved then
      statusTxt.setText("Saved! Changes permanent hain ab.")
      speakMcq("MCQ update ho gaya")
    else
      statusTxt.setText("Update hua is session ke liye, lekin file save fail hui. Storage permission check karein.")
    end
  end)

  ssd(AlertDialog.Builder(context).setTitle("EDIT MCQ").setView(sv).setPositiveButton("CLOSE",nil))
end

-- ============================================================
-- RENAME MCQ (change which category it belongs to) — reached
-- from long-press -> RENAME (Change Category)
-- ============================================================
function showRenameMCQCategory(m)
  local catLabels={}
  for _,c in ipairs(CATEGORIES) do table.insert(catLabels,c) end
  table.insert(catLabels,"+ CUSTOM CATEGORY...")
  ssd(AlertDialog.Builder(context).setTitle("Rename Category for "..m.id).setItems(catLabels,sc(function(dlg,which)
    if which==#catLabels-1 then
      local et=EditText(context); et.setHint("Naya category naam...")
      ssd(AlertDialog.Builder(context).setTitle("Custom Category").setView(et).setPositiveButton("SAVE",sc(function()
        local newCat=tostring(et.getText()):gsub("^%s+",""):gsub("%s+$","")
        if newCat=="" then return end
        m.category=newCat
        table.insert(CATEGORIES,newCat)
        local saved=saveMcqOverride(m)
        ssd(AlertDialog.Builder(context).setTitle(saved and "Renamed" or "Rename Failed").setMessage(m.id.." ab category '"..newCat.."' mein hai.").setPositiveButton("OK",nil))
      end)).setNegativeButton("CANCEL",nil))
    else
      local newCat=CATEGORIES[which+1]
      m.category=newCat
      local saved=saveMcqOverride(m)
      ssd(AlertDialog.Builder(context).setTitle(saved and "Renamed" or "Rename Failed").setMessage(m.id.." ab category '"..newCat.."' mein hai.").setPositiveButton("OK",nil))
    end
  end)).setNegativeButton("CANCEL",nil))
end

-- ============================================================
-- ONLINE SYNC (recursive detection + diagnostics)
-- ============================================================
local function looksLikeMcq(t)
  return type(t)=="table" and t.id and t.question and t.options and t.correct
end
local function collectMcqCandidates(node,depth,out)
  if depth>4 or type(node)~="table" then return end
  if looksLikeMcq(node) then table.insert(out,node); return end
  for k,v in pairs(node) do
    if type(v)=="table" then
      if looksLikeMcq(v) then table.insert(out,v) else collectMcqCandidates(v,depth+1,out) end
    end
  end
end

function testSyncUrl()
  if not _G.mcqSyncUrl or _G.mcqSyncUrl=="" then
    ssd(AlertDialog.Builder(context).setTitle("No URL").setMessage("Pehle Sync URL set karein.").setPositiveButton("OK",nil))
    return
  end
  httpGet(_G.mcqSyncUrl,nil,sc(function(rc,rs)
    local preview=rs:sub(1,400)
    ssd(AlertDialog.Builder(context).setTitle("Sync URL Test Result").setMessage("HTTP Status: "..rc.."\nResponse Length: "..#rs.." characters\n\nFirst 400 characters:\n\n"..preview).setPositiveButton("OK",nil))
  end))
end

function syncOnlineMcqs(silent)
  if not _G.mcqSyncUrl or _G.mcqSyncUrl=="" then
    if not silent then ssd(AlertDialog.Builder(context).setTitle("No Sync URL Set").setMessage("SETTINGS mein Sync URL set karein.").setPositiveButton("OK",nil)) end
    return
  end
  httpGet(_G.mcqSyncUrl,nil,sc(function(rc,rs)
    if rc~=200 then
      if not silent then ssd(AlertDialog.Builder(context).setTitle("Sync Failed").setMessage("HTTP "..rc).setPositiveButton("OK",nil)) end
      return
    end
    if rs=="null" or rs=="" then
      if not silent then ssd(AlertDialog.Builder(context).setTitle("Empty Data").setMessage("Firebase se null mila, URL check karein.").setPositiveButton("OK",nil)) end
      return
    end
    local ok,data=pcall(function() return cjson.decode(rs) end)
    if not ok or type(data)~="table" then
      if not silent then ssd(AlertDialog.Builder(context).setTitle("Sync Failed").setMessage("JSON valid nahi tha.").setPositiveButton("OK",nil)) end
      return
    end
    local candidates={}
    collectMcqCandidates(data,0,candidates)
    local added,duplicate=0,0
    for _,item in ipairs(candidates) do
      local exists=false
      for _,m in ipairs(MCQ_DB) do if m.id==item.id then exists=true break end end
      if exists then duplicate=duplicate+1
      else
        table.insert(MCQ_DB,item); added=added+1
        local found=false
        for _,c in ipairs(CATEGORIES) do if c==item.category then found=true end end
        if not found and item.category then table.insert(CATEGORIES,item.category) end
      end
    end
    dedupeQuestions()
    _G.mcqLastSync=os.date("%Y-%m-%d %H:%M")
    if not silent then
      ssd(AlertDialog.Builder(context).setTitle("Synced").setMessage("Naye add hue: "..added.."\nPehle se maujood: "..duplicate.."\nTotal ab: "..#MCQ_DB).setPositiveButton("OK",nil))
    end
  end))
end

-- ============================================================
-- SETTINGS
-- ============================================================
function showSetSyncUrl()
  local et=EditText(context); et.setHint("Firebase/GitHub raw JSON URL..."); et.setText(_G.mcqSyncUrl)
  local d=AlertDialog.Builder(context).setTitle("Set Online Sync URL").setMessage("Firebase Realtime DB .json endpoint ya GitHub raw JSON URL.")
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

  local pitchBtn=Button(context); pitchBtn.setText("VOICE PITCH: "..tostring(_G.mcqPitch))
  local pitches={0.8,1.0,1.2,1.4}
  pitchBtn.onClick=sc(function()
    local curIdx=1; for i,v in ipairs(pitches) do if math.abs(v-_G.mcqPitch)<0.01 then curIdx=i end end
    _G.mcqPitch=pitches[(curIdx%#pitches)+1]
    pcall(function() pitchBtn.setText("VOICE PITCH: "..tostring(_G.mcqPitch)) end)
  end)
  sl.addView(pitchBtn)

  local readOptBtn=Button(context); readOptBtn.setText(_G.mcqReadOptions and "AUTO-READ OPTIONS: ON" or "AUTO-READ OPTIONS: OFF")
  readOptBtn.onClick=sc(function()
    _G.mcqReadOptions=not _G.mcqReadOptions
    pcall(function() readOptBtn.setText(_G.mcqReadOptions and "AUTO-READ OPTIONS: ON" or "AUTO-READ OPTIONS: OFF") end)
  end)
  sl.addView(readOptBtn)

  local testVoiceBtn=Button(context); testVoiceBtn.setText("TEST VOICE")
  testVoiceBtn.onClick=sc(function() speakMcq("Ye aapki mojooda voice setting hai. Speed "..tostring(_G.mcqSpeed).." aur pitch "..tostring(_G.mcqPitch)..".") end)
  sl.addView(testVoiceBtn)

  local divider1=TextView(context); divider1.setText("--- Online Update / MCQ Websites ---"); divider1.setPadding(0,16,0,8); sl.addView(divider1)

  local syncSetBtn=Button(context); syncSetBtn.setText("SET ONLINE SYNC URL"); syncSetBtn.onClick=sc(function() showSetSyncUrl() end); sl.addView(syncSetBtn)
  local testSyncBtn=Button(context); testSyncBtn.setText("TEST SYNC URL (Raw Data Dekhein)"); testSyncBtn.onClick=sc(function() testSyncUrl() end); sl.addView(testSyncBtn)
  local syncNowBtn=Button(context); syncNowBtn.setText("SYNC ONLINE MCQs NOW"); syncNowBtn.onClick=sc(function() syncOnlineMcqs(false) end); sl.addView(syncNowBtn)
  local lastSyncTxt=TextView(context); lastSyncTxt.setText("Last Sync: ".._G.mcqLastSync); lastSyncTxt.setPadding(0,4,0,10); sl.addView(lastSyncTxt)

  local pakMcqsBtn=Button(context); pakMcqsBtn.setText("OPEN WEBSITES (In-App, no browser needed)"); pakMcqsBtn.onClick=sc(function() showWebsitesMenu() end); sl.addView(pakMcqsBtn)
  local addSiteBtn=Button(context); addSiteBtn.setText("+ ADD NEW WEBSITE TO LIST"); addSiteBtn.onClick=sc(function() showAddWebsiteDialog() end); sl.addView(addSiteBtn)

  local divider2=TextView(context); divider2.setText("--- About ---"); divider2.setPadding(0,16,0,8); sl.addView(divider2)
  local abt=Button(context); abt.setText("ABOUT THIS PLUGIN")
  abt.onClick=sc(function()
    ssd(AlertDialog.Builder(context).setTitle("ABOUT").setMessage("MY MCQ TRAINER\nDeveloped by Ali Razzaq\n\nTotal MCQs: "..#MCQ_DB.."\nLast Online Sync: ".._G.mcqLastSync.."\n\nAdd MCQs via the ADD NEW MCQ button (permanent, category auto-detected), local batch .lua files, or online sync.").setPositiveButton("OK",nil))
  end)
  sl.addView(abt)

  ssd(AlertDialog.Builder(context).setTitle("SETTINGS").setView(sv).setPositiveButton("DONE",nil))
end

-- ============================================================
-- MAIN SCREEN
-- ============================================================
local ML=LinearLayout(context); ML.setOrientation(1); ML.setPadding(12,12,12,12)
local outerSV=ScrollView(context); outerSV.addView(ML)

local devTxt=TextView(context); devTxt.setText("Developed by Ali Razzaq"); devTxt.setTextSize(14); ML.addView(devTxt)
local totalTxt=TextView(context); totalTxt.setText("TOTAL MCQs AVAILABLE: "..#MCQ_DB); totalTxt.setTextSize(18); totalTxt.setPadding(0,4,0,14); ML.addView(totalTxt)

-- 1) CHOOSE CATEGORY
local catBtn=Button(context); catBtn.setText("1. CHOOSE CATEGORY"); ML.addView(catBtn)
catBtn.onClick=sc(function() pickCategory("Choose Category",browseCategory) end)

-- 2) PLAY QUIZ
local quizBtn=Button(context); quizBtn.setText("2. PLAY QUIZ"); ML.addView(quizBtn)
quizBtn.onClick=sc(function() pickCategory("Play Quiz - Select Category",startQuiz) end)

-- 3) ADD MCQ
local addMcqBtn=Button(context); addMcqBtn.setText("3. ADD MCQ"); ML.addView(addMcqBtn)
addMcqBtn.onClick=sc(function() showAddMCQ() end)

-- 4) SETTINGS
local settingsBtn=Button(context); settingsBtn.setText("4. SETTINGS"); ML.addView(settingsBtn)
settingsBtn.onClick=sc(function() showSettings() end)

local divider3=TextView(context); divider3.setText("--- More Tools ---"); divider3.setPadding(0,16,0,8); ML.addView(divider3)

local searchBtn=Button(context); searchBtn.setText("SEARCH MCQs"); ML.addView(searchBtn)
searchBtn.onClick=sc(function() showSearch() end)

local bmBtn=Button(context); bmBtn.setText("MY BOOKMARKS"); ML.addView(bmBtn)
bmBtn.onClick=sc(function() showBookmarks() end)

local tipTxt=TextView(context); tipTxt.setText("Tip: Kisi bhi MCQ ko list mein long-press karke Edit / Rename / Share / Copy kar sakte hain."); tipTxt.setTextSize(12); tipTxt.setPadding(0,10,0,0); ML.addView(tipTxt)

if _G.mcqSyncUrl and _G.mcqSyncUrl~="" then syncOnlineMcqs(true) end

ssd(AlertDialog.Builder(context).setTitle("MY MCQ TRAINER").setView(outerSV).setPositiveButton("EXIT",nil))
