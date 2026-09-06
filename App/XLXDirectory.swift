import Foundation

// Data file: the bundled reflector snapshot dominates the line count.
// swiftlint:disable file_length

struct XLXReflector: Identifiable {
    let name: String
    let host: String
    let country: String

    var id: String { name }
}

// Bundled snapshot of the live XLX registry (xlxapi.rlx.lu), reflectors
// seen within 24h of the snapshot, generated 2026-09-06. Hostnames are
// the reflector dashboards where they resolve, else the registered IP.
// Stored as data rather than 800+ struct literals to keep compiles fast.
enum XLXDirectory {
    static let all: [XLXReflector] = xlxRawDirectory.split(separator: "\n").compactMap { line in
        let parts = line.split(separator: "|", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        return XLXReflector(name: String(parts[0]), host: String(parts[1]), country: String(parts[2]))
    }

    static func reflector(forHost host: String) -> XLXReflector? {
        let trimmed = host.trimmingCharacters(in: .whitespaces)
        return all.first { $0.host == trimmed }
    }

}

private let xlxRawDirectory = """
XLX000|xlx000.dmr.net.br|Brazil
XLX001|217.154.120.107|Italy
XLX002|xlx.capwork.cn|China
XLX003|reflektor.koledzyzradia.pl|Poland
XLX004|121.43.36.126|Taizhou-China
XLX005|xlx005.freedmr.uk|United Kingdom
XLX006|xlx006.crigan.us|United States
XLX007|dcs007.xreflector.net|Netherlands
XLX008|xlx.py1ip.com|Brazil
XLX009|www.hamtalk.net|Taiwan
XLX00A|94.177.201.198|Italy
XLX00B|xlx00b.mydns.jp|Japan
XLX010|dcs010.xreflector.net|Sweden
XLX011|dcs011.xreflector.net|Belgium
XLX012|xlx012.ddns.net|Poland
XLX013|xlx.bigvortex.com|United States
XLX014|dcs014.xreflector.net|Australia
XLX015|dcs015.xreflector.net|Germany
XLX016|xrf016.xreflector-jp.org|Japan
XLX017|31.14.140.141|Poland
XLX019|dcs019.xreflector.net|Czech Republic and Slovakia
XLX020|xlx020.k2ie.net|United States
XLX021|xlx.projekt-pegasus.net|Germany
XLX022|xlx022.hamradio.services|Denver, CO, USA
XLX023|xlx023.ddns.net|Bulgaria
XLX024|xlx024.ddns.net|Poland
XLX026|xlx026.net|Brazil
XLX027|xlxaras.duckdns.org|Italy
XLX028|xlx.k5wh.net|United States
XLX029|adk.bigvortex.com|United States
XLX030|xlx030.ardv.at|Austria
XLX031|xlx.pistar.eu|Germany
XLX032|xlx032.epf.lu|Luxembourg
XLX033|xlx033.hamdigital.fr|France
XLX034|ag5aa.com|United States
XLX035|xrf035.wa7dre.org|Spokane, WA, USA
XLX036|xlx036.zacharewicz.info|Poland
XLX037|xlx037.ddns.net|United States
XLX038|xlx038.dyndns.org|United States
XLX039|xlx039.dyndns.org|United States
XLX040|xlx040.dstar-portugal.pt|Portugal
XLX041|206.81.1.250|Puerto Rico
XLX042|de9956.ddns.net|GB-Wales
XLX043|xlx043.pauldingares.com|USA-Georgia
XLX044|xlx044.qsos.uk|United Kingdom
XLX045|urf045.pennlinkgroup.com|United States
XLX046|xlxchile.radioaficion.pro|CHILE
XLX047|202.171.147.58|JAPAN
XLX048|xurev.ddns.net|Spain
XLX049|xlx049.dyndns.org|United States
XLX050|xlx050.bsdworld.org|United States
XLX051|2141.adn.systems|SPAIN
XLX052|xrf052.xreflector-jp.org|Japan
XLX053|xlx053-n0mis.ddns.net|United States
XLX054|xlx054.ddns.net|Poland
XLX055|52.80.4.154|China
XLX056|66.42.126.197|United States
XLX057|212.107.141.130|Sweden
XLX058|xrf058.xreflector-jp.org|Japan
XLX059|dstar.ridigitallink.net|United States
XLX060|45.76.133.116|United Kingdom
XLX061|xlx.bridge.oarc.uk|United Kingdom
XLX062|xlx.superlink.qsl.br|Brazil
XLX063|manfred-lichtenstern.de|Germany
XLX064|122.222.1.50|Aichi Japan
XLX065|xlx.ustriplenickel.com|United States
XLX066|209.141.44.203|Shandong, China
XLX067|xlx067.duckdns.org|United States
XLX068|xlx068.ircddb.it|Italy
XLX069|grupoelite.es|Spain
XLX070|xlx.dstar.com.br|Brazil
XLX071|xrf.elechomebrew.com|Daegu, South Korea
XLX072|xlx.m0ned.org|United Kingdom
XLX073|xlx073.wiredham.org|United States
XLX074|xlx074.bh1nyr.net|Beijing, China
XLX075|xlx.flg-wiresx.cloud|United States
XLX076|xrf076.xreflector-jp.org|Japan
XLX077|xe1dvi.crabdance.com|USA-MEX
XLX078|xlx.bh4crv.com|China
XLX080|xrf080.mydns.jp|Japan
XLX081|xrf081.mydns.jp|Japan
XLX082|xlx082.hamradio.services|Denver, CO, USA
XLX083|www.cl-link.cl|CHILE
XLX084|xlx.dn2ane.de|Germany
XLX085|xrf085.mydns.jp|Japan
XLX086|140.179.13.243|China
XLX087|ballarat-australia.net|Ballarat - Australia
XLX088|xlx088.pa4tw.nl|Netherlands
XLX089|xlx089.newenglanddigitalradio.com|United States
XLX090|kurpie.ddns.net|Poland
XLX091|217.142.144.62|China
XLX092|xlx092.duckdns.org|Schweiz
XLX093|famiuse.ddns.net|Italy
XLX094|xlx.utahdrn.org|United States
XLX095|xrf095.xreflector-jp.org|Japan
XLX096|096busan.duckdns.org|KOREA
XLX097|xlx097.newenglanddigitalradio.com|United States
XLX098|xrf098.mydns.jp|Nagoya JAPAN
XLX099|vmi2909834.contaboserver.net|Hungary
XLX100|d-star.lt|Lithuania
XLX101|xlx.lt|Lithuania
XLX102|xlx102.xlxreflector.org|USA - Florida
XLX103|xlx103.xlxreflector.org|Canada
XLX104|xlx104.xlxreflector.org|USA - Georgia
XLX105|ref105.dstar.com.br|Brazil
XLX106|urf106.com|United States
XLX108|suzaka.f5.si|Japan
XLX109|d-star.f5.si|Japan
XLX110|140.82.14.24|United States
XLX111|xrf111.xreflector-jp.org|Japan
XLX112|xlx.jayceera.in|United States
XLX113|xlx.foerdefunk.de|Germany
XLX114|xlx114.duckdns.org|Finland
XLX115|xlx115.hb9vd.ch|Switzerland
XLX116|xlx116.cisaragrigento.it|Italy
XLX117|xlx117.ddns.net|Uruguay
XLX119|xlx119.duckdns.org|Greece
XLX120|xlx120.com|United States
XLX121|xlx121.ddns.net|Italy
XLX122|194.37.80.40|Greece
XLX123|xlx.home64.de|Germany
XLX125|79.172.213.236|Hungary
XLX126|jrlinden.zapto.org|United States
XLX127|xlx127.ddns.net|SPAIN
XLX128|xlx128.radiohub.ar|Argentina
XLX129|xlx129.comfusion.co.nz|New Zealand
XLX130|xlx130.nh6fu.com|United States
XLX131|xlx131.pe1er.nl|Netherlands
XLX132|xlx132.dstar.radom.pl|Poland
XLX133|xlx133.ddns.net|United Kingdom
XLX134|xlx134.ddns.net|Poland
XLX135|xlx.hopto.org|United Kingdom
XLX136|xlx136.f5.si|Kanazawa Japan
XLX137|xlx137.mywire.org|United States
XLX138|xlx138.freeddns.org|Thailand
XLX139|xlx139.dyndns.org|United States
XLX140|xlx140.nix.pt|Europe
XLX141|xlx.vadigital.network|United States
XLX142|xlx.k7jsx.net|United States
XLX143|xlx143.duckdns.org|Italy
XLX145|URF145.pennlinkgroup.com|United States
XLX146|131.186.42.239|Japan
XLX147|G4SKM.duckdns.org|United Kingdom
XLX148|xlx.hs3tdi.com|Thailand
XLX149|xlx.pwk.ac.th|Thailand
XLX150|xlx150.ddns.net|United States
XLX151|xlx151.hamonsite.com|USA - North MS
XLX152|kj4dhf.ddns.net|United States
XLX153|xlx153.dyndns.org|United States
XLX155|thedive155.com|TheDive USA
XLX157|xlx157.dyndns.org|Italy
XLX158|d-star2.f5.si|Japan
XLX159|xlx159.whiskey7.site|Olympia, Washington USA
XLX160|xrf160.xreflector-jp.org|Japan
XLX161|xlx161.eu|Republic of BULGARIA
XLX162|44.32.81.27|Thailand
XLX163|45.143.93.75|Samara
XLX164|reflector.k4fsg.net|United States
XLX165|XLX165.ddns.net|Greece
XLX166|79.137.85.89|Italy
XLX167|XLX167-n0mis.ddns.net|United States
XLX168|xlx168.mydns.jp|Japan
XLX169|xlx169.26269.de|Germany
XLX170|xlx170.hamoverip.com|United States
XLX171|xlx.r3pij.ru|Russia
XLX172|jm1fvo.mydns.jp|Japan
XLX173|xlx.lagranderadioclub.com|United States
XLX174|xlx.digitalfunk-nordost.de|Germany
XLX176|xrf176.xreflector-jp.org|Japan
XLX177|xlx.iz3mez.it|Italy
XLX178|xlx.buxton.radio|Buxton, GB
XLX179|atzxlx.ddns.net|NE Wales
XLX180|xlx180.warn.org|Ohio USA
XLX181|ny1usxlx.ddns.net|United States
XLX182|dvmq.ddnsfree.com|Korea
XLX184|sq5buj.pl|Poland
XLX185|xlx185.hamradio.onl|United States
XLX187|multinode.fupcinternational.com|United States
XLX188|xlx.bitbybithams.com|United States
XLX189|46.181.171.44|Россия
XLX190|xlx.argentinaroom.com.ar|Argentina
XLX191|cqlaplata.ddns.net|Argentina
XLX192|jg5eqv.mydns.jp|Japan
XLX194|xlx.smslowianin.pl|POLAND
XLX195|134.122.12.176|United States
XLX196|xlx196.dyndns.org|Canada
XLX197|xlx197.dyndns.org|Canada
XLX198|xlx198.ddns.net|Argentina
XLX199|xlx.argentinanetwork.ar|ARGENTINA
XLX200|ec2ut.ddns.net|Spain
XLX201|xlx201.amgcloud.es|SPAIN
XLX202|xlx202.clickandhope.com|United Kingdom
XLX203|50.116.36.65|United States
XLX204|xlx204.ddns.net|Netherlands
XLX205|www.raw.usk4lls.com|United States
XLX206|44.31.191.62|Ireland
XLX207|dash-xlx207.duckdns.org|Bedford United Kingdom
XLX208|xlx208.f5kav.fr|France
XLX209|xlx.smokyshare.com|United States
XLX210|adn2061.be|Belgium
XLX211|xlx211.radio-nw.net|Spain
XLX212|xlx212.dstar.club|United States
XLX213|xlx.wp4ssb.net|Puerto Rico
XLX214|xlx214.xreflector.es|ES
XLX215|hadars-reflector.ddns.net|United Kingdom
XLX216|xlx216.n8usk.com|United States
XLX217|xlx217.dynamic-dns.net|United States
XLX218|xlx218.chaverimradio.com|United States
XLX219|108.61.87.174|United States
XLX220|xlx220.sapotech.com|Miyazaki Japan
XLX221|xrf221.dyndns.org|United States
XLX222|172.233.145.145|Bahrain
XLX223|44.27.136.19|United States
XLX225|xrf225.xreflector-jp.org|Japan
XLX226|44.32.81.143|Thailand
XLX227|xlx227.hamnet.ro|Romania
XLX228|XLX228.myddns.me|United States
XLX229|dstar.hamnet.xyz|Switzerland
XLX230|xlx230.ok2it.com|Czech Republic
XLX231|xlx.is0.org|Sardinia Island
XLX232|rudinet.giize.com|Italy
XLX233|g7usp.interadd.co.uk|United Kingdom
XLX234|82.165.7.197|United Kingdom
XLX235|ddmtc.ddns.net|United Kingdom
XLX236|xlx236.jdlspeedy.us|United States
XLX237|xlx237.eastcoastreflector.com|United States
XLX238|xlx238.d-star4all.dk|Denmark
XLX239|reflector.kb2idx.com|United States
XLX240|xlx.hb9v.ch|Switzerland
XLX241|xlxrem.xreflector.es|Spain
XLX242|66.42.84.85|United Kingdom
XLX243|soky.online|United States
XLX244|xlx.rz44.com|United States
XLX245|xlx245.sub.h-sol.jp|Japan
XLX246|xlx.mkagawa.com|N California, USA
XLX247|xlx.oz-dmr.network|United Kingdom
XLX248|xlx248.freestar.network|United Kingdom
XLX250|xlx.n5bdj.com|United States
XLX251|xlx251.ddns.net|Greece
XLX252|xlx252.ddns.net|Greece
XLX254|xlx254.ki5kzu.net|United States
XLX255|xrf255.reflector.up4dar.de|Ukraine
XLX256|xrf256.swl.in.ua|Ukraine
XLX257|xlxd257.uw0wu.com|Ukraine
XLX258|ref258.ddns.net|United States
XLX259|xlx.olympy.org.ua|Ukraine
XLX260|xlx.do9ck.de|Germany
XLX262|xlx.prgm.org|Germany
XLX263|xlx.afu-kiel.de|Germany
XLX264|52.2.131.118|United States
XLX265|xlx.n8mfn.club|United States
XLX266|aderdigitales.ddns.net|Spain
XLX267|xlx.ct1ebq.com|Portugal
XLX268|xlx268.from-ct.com|Portugal
XLX269|urf269.db0htv.de|Germany
XLX270|xlx270.epf.lu|Luxembourg
XLX271|xlx271.ddnss.org|Germany
XLX272|xlxd.9y4c.com|Trinidad and Tobago
XLX273|vk3agk.net.au|AU
XLX275|xlx275.superlink.qsl.br|Brazil
XLX277|xlx277.bitbybithams.com|United States
XLX279|xlx.jl-networking.co.uk|United Kingdom
XLX280|iz8izj.ddns.net|Italy
XLX281|xlx.kd7lmn.com|United States
XLX282|xlx282.orangesun.org|United Kingdom
XLX283|xlx283.mydns.jp|JAPAN
XLX284|dmrbulgaria.net|Bulgaria
XLX285|457430.ip.hamvoip.org|United States
XLX286|xlx286.dmrturkiye.com|TÜRKiYE
XLX288|ic8uoh.ddns.net|Italy
XLX290|ct7apz.zapto.org|Portugal
XLX291|xrf291.xreflector-jp.org|Japan
XLX294|xlx.dmr.net.mk|Macedonia
XLX295|xlx295.dyndns.org|United States
XLX296|xlx296.h-sol.jp|Japan
XLX298|xrf298.mydns.jp|NAGOYA JAPAN
XLX299|www.xlx299.nz|New Zealand
XLX300|xlx300.net|Brazil
XLX301|xlx301.stagecraft.cx|Australia
XLX302|xlx.vk2cjr.au|Australia
XLX303|coloradodigital.duckdns.org|United States
XLX304|304.ve5aas.ca|Canada
XLX305|xlx.m5adi.com|Manchester, UK
XLX306|urf306.warg.org.au|Australia
XLX307|xlx307.ddns.net|United States
XLX308|coloradu.co|United States
XLX309|xlx.ke4tzn.com|United States
XLX310|srv.ysf-france.fr|FR YSF France
XLX311|ernix.de|Germany
XLX312|xlx.dmr-marc.net|United States
XLX313|94.177.160.244|Italy
XLX314|xlx314.ddns.net|Argentina
XLX317|xlx317.duckdns.org|United States
XLX318|xlx.kn6rbp.com|United States
XLX319|92.62.226.78|Czechia
XLX320|ea4grr.ddns.net|EXTREMADURA
XLX321|xlxd.net.drc.bz|Italy
XLX322|76.219.234.40|United States
XLX323|xlx323.ddns.net|United States
XLX324|192.253.246.36|United States
XLX325|xlx325.nt1k.com|United States
XLX326|xrf326.xreflector-jp.org|Japan
XLX327|xlx327.from-ak.com|United States
XLX328|212.237.33.114|Switzerland
XLX329|xrf329.aa0.netvolante.jp|Japan
XLX330|xlx.n8ei.com|United States
XLX331|64.237.214.46|Coamo PR
XLX332|xlx332.ddns.net|Italia - Puglia - Lecce - Squinzano
XLX333|xlx333.bvc.pl|Poland
XLX334|alabamalink.info|United States
XLX335|xlx.hamfusion.com|United States
XLX337|multi.kc5jmj.com|United States
XLX339|xlx339.de|Germany
XLX340|prboriken.ddns.net|Puerto Rico
XLX342|xlx342.websdr-ea1url.es|Spain
XLX344|k6egg.hamradio.one|United States
XLX345|xlx345.pb1sam.nl|Netherlands
XLX346|xrf346.xreflector-jp.org|Japan
XLX347|xlx.kq4afy.radio|Florida USA
XLX349|xlx.poa.nyc|United States
XLX350|xlx350.f5.si|Kanazawa Japan
XLX351|xlx351.dyndns.org|United States
XLX352|xlx352.duckdns.net|United States
XLX353|xlx353.ei3rcw.ampr.org|Ireland
XLX354|xlx354.qsos.uk|United Kingdom
XLX355|223.95.197.217|China
XLX356|zlatix.com|Bulgaria
XLX357|xlx357.arrg.club|your_country
XLX358|xlx358.signalsphere.org|United States
XLX359|xlx359.com|Bulgaria
XLX360|360.unifiedradios.com|United States
XLX361|manjello.com|United States
XLX363|urf363.merg.biz|Germany
XLX364|xlx364.n1xrs.net|United States
XLX365|xlx365.ddns.net|GREECE
XLX369|72.89.122.8|United States
XLX370|xlx370.selfip.com|Italy
XLX371|xlx371.selfip.com|Italy
XLX372|xlx372.kf0lpt.com|United States
XLX373|xrf373.mydns.jp|Kyoto Japan
XLX374|xlx.9z4rg.com|Trinidad and Tobago - REACT
XLX375|xlx375.bfrr.by|Belarus
XLX376|xlx376.nikolabs.net|Murica!-zl
XLX377|xlx.toytron.com|Curacao
XLX379|nfoxlxnorcal.dyndns.org|Murphys, Ca. USA
XLX380|xlx380.repeatme.ca|Canada
XLX381|xlx.trianglenc.net|United States
XLX384|xlx.MRN.mywire.org|United States
XLX385|xlx.mrn2.mywire.org|United States
XLX386|xlx.foxhole.radio|United States
XLX387|xlx.rkelzas.ba|Bosnia & Herzegovina
XLX388|xlx.alecwasserman.com|United States
XLX390|xlx390.ddns.net|Italy
XLX393|xrf393.mydns.jp|JAPAN
XLX394|xlx394.ddns.net|Nicolas ON4VK
XLX395|xlx395.grupporadiofirenze.net|Italy
XLX396|xlx.lattuga.org|United States
XLX397|64.121.36.162|United States
XLX398|k4ern.net|United States
XLX400|pp5au.net|Brazil
XLX401|pankoe.no-ip.biz|United States
XLX402|synoweb.ddns.net|Flémalle
XLX403|xlx403.qsl.me|CANADA
XLX404|xlx.bendiksverden.net|Norway
XLX405|xlx405.repeatme.ca|Canada
XLX406|xlx406.ddns.me|United States
XLX407|n7wwl.ddns.net|United States
XLX408|xlx408.ddns.me|Philippines
XLX409|w6tnt.com|United States
XLX410|qrz.com|United States
XLX411|socaldigitalk.com|United States
XLX412|xrf412.xreflector-jp.org|Japan
XLX413|xlx413.mydns.bz|Japan
XLX414|xlx.iq3gdb.net|Italy
XLX415|kj6vrc.com|United States
XLX416|xlx416.repeatme.ca|Canada
XLX417|xlx417.repeatme.ca|Canada
XLX418|xlxd.petitpingouin.org|Canada
XLX419|xlx419.dyndns.org|United States
XLX420|xlx.ve2sus.com|Canada
XLX421|dl-nordwest.com|Germany
XLX422|xlx422.lu9hoo.com.ar|Argentina
XLX423|44.27.137.39|United States
XLX424|gpj-hamradio.servebeer.com|La Haye Centre France
XLX425|xlx.rfelettronica.com|Italy
XLX426|xlx-mx.ddns.net|Mexico
XLX427|xlx427.repeatme.ca|Canada
XLX429|66.154.114.23|Managua, Nicaragua
XLX42D|xlx42d.dyndns.org|france
XLX430|xlx430.mydns.jp|Japan
XLX431|xrf431.xreflector-jp.org|Japan
XLX432|xlx.vkradio.com|Australia
XLX433|217.160.121.75|Germany
XLX434|107.152.38.36|SPAIN
XLX435|xlx435.unusualperson.com|United States
XLX437|109.172.7.162|your_country
XLX438|tonaru.net|JAPAN
XLX439|italyi4multip.ddns.net|Italy
XLX440|xrf440.e-kyushu.net|Japan
XLX441|xrf441.xreflector-jp.org|Japan
XLX442|xlx.k1dbc.com|United States
XLX443|xlx443.dd8ba.com|Germany
XLX444|51.83.46.75|Netherlands
XLX445|xrf445.dynu.net|United States
XLX446|xrf446.dynu.net|United States
XLX447|xlx447.radiorubka.org|Apatity
XLX448|xlx.wa9hxl.com|Wisconsin, USA
XLX449|cw.ossdr.com|United States
XLX450|casaos.dvham.com|Korea
XLX451|xlx.dl3mc.de|NRW / Germany
XLX452|194.87.210.74|Murman
XLX453|61.239.171.240|Hong Kong, China
XLX454|xlx454.hkham.net|Hong Kong, China
XLX455|hst-new.hst.tu-dortmund.de|Germany
XLX456|xlx456.de|Germany
XLX457|ysf.kansascitywide.com|United States
XLX458|xxlx.w0fh.net|United States
XLX459|xrf459.xreflector-jp.org|Japan
XLX460|xlx460.duckdns.org|United States
XLX462|xlx462.ddns.net|France
XLX465|62.109.27.102|your_country
XLX467|xlx467.snwlab.net|Japan
XLX470|xlxnettalk.dyndns.org|Northern Ca. USA
XLX474|xlx474.duckdns.org|Poland
XLX475|118.27.35.184|Hiroshima JAPAN
XLX476|171.33.84.7|France
XLX477|g7rpg.hubnetwork.uk|United Kingdom
XLX479|imrs.amcomm.network|United States
XLX480|xlx480.edsreflector.com|United States
XLX483|xlxcwops.dyndns.org|Pine Grove, Ca. USA
XLX484|xlx.reonet.no|Norway
XLX485|xlx485.carc-nc.us|North Carolina, USA
XLX486|171.33.87.233|France
XLX487|31.163.198.165|USSR
XLX489|45.77.126.133|United States
XLX490|carmarthenars.ddns.net|United Kingdom
XLX492|92.118.113.80|United States
XLX493|xlx493.w0chp.radio|Minn. USA
XLX494|xlx.netasylum.com|United States
XLX495|185.255.132.168|USSR
XLX497|xlx497.endoria.net|Netherlands
XLX500|xlx500.org|Australia
XLX501|www.xlx501.xreflector.es|El Salvador
XLX502|200.94.250.24|Guatemala
XLX503|xlx.kansascitywide.com|United States
XLX504|38.7.31.70|Honduras
XLX505|vk7hse.duckdns.org|Australia
XLX506|126.111.77.170|Ehime Japan
XLX507|hp1cdw.ddns.net|Panama
XLX508|xlx-owl.de|Germany
XLX510|xrf510.xreflector-jp.org|Japan
XLX511|xlx511.ddns.net|Slovenia
XLX512|xlx512.newcastle-dstar.com|United States
XLX514|xrf514.xreflector-jp.org|Japan
XLX515|xrf515.xreflector-jp.org|Japan
XLX516|xlx.bd4two.site|CN
XLX517|xlx517.radiosc.net|United States
XLX518|xlx518.n18.de|Germany
XLX519|xrf519.ve3zin.com|Canada
XLX520|520ref.theworkpc.com|United States
XLX522|xlx.lucifernet.com|Malaysia
XLX523|edone.lucifernet.com|Malaysia
XLX524|xlx.lancs.fm|United Kingdom
XLX525|xlx525.webhop.net|North Carolina, USA
XLX528|it9frnag.ns0.it|Italy
XLX529|80.211.229.187|Italy
XLX530|xlx530.hopto.org|New Zealand
XLX532|xlx532.oevsv.at|Austria
XLX538|xrf538.mydns.jp|Osaka Japan
XLX540|74.207.225.205|Monterrey Mexico
XLX543|croatia-digital-group.com|CROATIA
XLX545|xlx545.pennlinkgroup.com|United States
XLX546|71.91.41.20|United States
XLX547|130.51.20.196|USA - California
XLX548|kb5sj.com|United States
XLX551|120.27.213.225|China
XLX555|0la8wrdmqv91ywa4.myfritz.net|Germany
XLX556|xlx556.kq4tnv.net|United States
XLX559|5.249.151.6|Poland
XLX560|xrf560.xreflector-jp.org|Japan
XLX561|xrf561.xreflector-jp.org|Japan
XLX564|8.137.165.149|P.R.China'
XLX565|66.42.70.161|Canada
XLX567|xlx.suonnet.rs|Serbia
XLX568|xlx568.hs8as.com|Thailand
XLX569|151.97.13.145|Italy
XLX570|xlx.repeater.net|United States
XLX573|45.79.218.91|United States
XLX575|xlx575.lobo.net|United States
XLX576|refleqtion.net|United States
XLX578|airport.bitbybithams.com|United States
XLX580|xlx580.f5.si|Kanazawa Japan
XLX581|xlx581.py2ko.com|Brazil
XLX583|xrf583.mydns.jp|JAPAN
XLX585|xlx585.net|ITALIA IPv4+IPv6+AMPR 44
XLX586|xlx586.ari-rivarolo.org|ITALIA IPv4+IPv6
XLX590|xlx590.mydns.jp|Japan
XLX595|xlx.xlx595.net|Italy
XLX598|dx6cn.duckdns.org|PH
XLX599|xrf599.xreflector-jp.org|Japan
XLX600|dvsph.net|United Kingdom
XLX601|172.234.206.136|United States
XLX604|xlx604.jedham.uk|United Kingdom
XLX606|87.106.55.42|Italy
XLX607|xlx.somberjp.com|United States
XLX608|xrf608.xreflector-jp.org|Fukuoka Japan
XLX610|reteradio.cisartrieste.it|ITALY
XLX613|167.114.144.141|Canada
XLX616|xlx616.aivian.org|China
XLX618|ysf.kn6rbp.com|United States
XLX620|xlx620.starfield.link|Japan
XLX621|urf.hrcc.link|United States
XLX626|3907.hamradio.one|United States
XLX628|xlx628.scumm.it|Italy
XLX630|xrf630.xreflector-jp.org|Japan
XLX632|xlx632.dstar.corbettdigital.net|United States
XLX633|xlx.ke0tcf.radio|United States
XLX634|xrf634.xreflector-jp.org|Japan
XLX635|xlx.dl4ybg.de|Germany
XLX636|xlx.ham.lv|Latvia
XLX637|w6idk.com|United States
XLX639|xrf639.mydns.jp|JAPAN
XLX642|xlx.qsl.lt|Lithuania
XLX644|b8fe0a845997.sn.mynetname.net|Greece
XLX645|xlx645.pennlinkgroup.com|United States
XLX647|hs5blo.fortiddns.com|Thailand
XLX649|doghousenet.com|United States
XLX654|xrf654.xreflector-jp.org|Japan
XLX655|xlx655.ddns.net|South Africa
XLX656|173.230.139.250|United States
XLX660|xlx660.ddns.net|JAPAN
XLX661|jg6yjw.mydns.jp|Japan
XLX662|662.duckdns.org|United States
XLX665|xrf665.xreflector-jp.org|Japan
XLX666|95.179.179.175|United Kingdom
XLX667|217.154.116.45|Italy
XLX668|urf.n9hxr.radio|United States
XLX669|xlx.shadowtronics.org|United States
XLX672|xlx672-dash.pistar.uk|United Kingdom
XLX673|xrf673.xreflector-jp.org|Japan
XLX674|m0unc.co.uk|United Kingdom
XLX676|676.n0mb.net|United States
XLX678|xlx.m0lxq.com|United Kingdom
XLX679|xlx.borris.me|United States
XLX680|xlx680.f5.si|Kanazawa Japan
XLX683|198.46.160.211|United States
XLX687|xlx.digitalradioke4qcm.wiki|United States
XLX688|xlx688.ab8m.net|United States
XLX689|97.107.128.47|United States
XLX693|44.27.131.126|United States
XLX697|xlx697.vr2mw.com|HONG KONG
XLX698|xrf698.xreflector-jp.org|Japan
XLX699|xlx699.se|Sweden
XLX700|xlx.pd3rfr.nl|Netherlands
XLX701|xrf701.xreflector-jp.org|Japan
XLX704|149.28.43.188|United States
XLX705|xrf705.xreflector-jp.org|Japan
XLX706|xlx706.iz0rin.it|Italy
XLX707|dstar.digitalevoice.nl|Netherlands
XLX708|xrf708.xreflector-jp.org|Japan
XLX710|dstar.pa7lim.nl|Netherlands
XLX711|k4zxx.net|United States
XLX713|ysf.k0ros.net|United States
XLX714|xlx714.radioaficionats.com|Catalunya
XLX715|xlx-urcat.ddns.net|CATALUNYA
XLX716|xlx716.dmr-peru.net|Peru
XLX717|88.159.31.251|NL
XLX718|718xlx.ddns.net|Italy
XLX719|crsjo.duckdns.org|Costa Rica
XLX720|xlx.colorado720.com|United States
XLX721|xlx721.dyndns.org|United States
XLX722|xlx722.k9chu.com|United States
XLX723|xlx723.sv1bgm.net|Greece
XLX727|xlx727.gleeze.com|Thailand
XLX729|xlx729.huskyno.se|United Kingdom
XLX730|sdradio.cl|CHILE
XLX732|xlx.octanenetwork.net|United States
XLX733|w2bn-xlx.na9x.com|United States
XLX734|15.204.230.203|Venezuela
XLX735|pr-xlx.k2ln.info|United States
XLX736|xlx736.ddns.net|Italy
XLX737|83.212.170.243|Greece
XLX738|57.129.134.218|United Kingdom
XLX741|xrf741.xreflector-jp.org|Japan
XLX742|xlx-hc3.ddns.net|Ecuador
XLX743|xlx743.ddns.net|Ecuador
XLX744|xlx-hp3.dnsup.net|Panama
XLX745|xlx745.mydns.jp|Japan
XLX747|xlx747.de|Germany
XLX748|xlx748.dyndns.org|United States
XLX749|k2hzexlx.duckdns.org|United States
XLX750|xlx750.nz|New Zealand
XLX751|xlx751.drgau.au|Australia
XLX755|xlx.radioamateur.tk|Corsica
XLX757|xrf757.openquad.net|United States
XLX758|xlx758.0t0.jp|Japan
XLX760|xlx760.ddns.net|Perlas ng Silangan
XLX763|xlx.morten.dog.|United States
XLX765|ik1-342-31132.vs.sakura.ne.jp|Japan
XLX766|xlx.amrase.org.br|Brazil
XLX767|takshino.mydns.jp|Japan
XLX768|xlx.hamradio.pt|Portugal
XLX770|xrf770.mydns.jp|Tokushima JAPAN
XLX771|xlx771.duckdns.org|Korea
XLX772|xlx772.duckdns.org|Korea
XLX773|xlx773.iz0rin.it|Italy
XLX774|xlx774.ve2cyh.org|Canada
XLX775|xlx775.iz2qcp.it|Italy
XLX777|ealink.es|SPAIN
XLX778|xlx.hblink.kutno.pl|Poland
XLX781|xrf781.xreflector-jp.org|Japan
XLX787|46.41.1.96|Germany
XLX789|rf.ha.lc|United States
XLX790|xlx790.vdbg.nl|Netherlands
XLX794|xrf794.xreflector-jp.org|Japan
XLX797|xrf797.xreflector-jp.org|Japan
XLX798|92.247.20.2|Bulgaria
XLX799|xlxsof.ddns.net|Bulgaria
XLX800|xlx800.ddns.net|Bulgaria
XLX801|oe1phs.ddns.net|AUSTRIA - VIENNA OE1
XLX803|xlxcloverradio.digital|United States
XLX804|cloverxlxham.digital|United States
XLX805|xlx805.ddns.net|United States
XLX806|xlx806.ddns.net|D-STAR Austria Netz
XLX807|116.91.197.3|Japan
XLX810|130.51.22.53|United States
XLX811|dstarjapan.pa7lim.nl|Japan
XLX812|xrf812.xreflector-jp.org|Japan
XLX814|xlx814.kr3l.org|United States
XLX815|xlx815.we0fun.com|United States
XLX816|xlx816.w4fe.com|USA - Levy Co, FL
XLX817|xlx817.w4fe.com|USA - Citrus Co, FL
XLX818|xlx818.hamnew.com|Thailand
XLX819|xlx.va2dfk.com|Canada
XLX820|xlx820.com|Australia
XLX822|xlx821.dstarthailand.com|Thailand
XLX823|kd2qqv.ddns.net|United States
XLX824|vk4rjwm17.com|Australia
XLX825|xlx.g6phf.co.uk|GB
XLX826|8.163.29.23|China
XLX827|xlx.kd5dfb.net|United States
XLX828|xlx.wm4wm.com|United States
XLX829|xlx829.spartanpcsecurity.com|United States
XLX830|lonestarlinksystem.com|United States
XLX831|xlx831.ddns.net|Santa Cruz, CA, USA
XLX833|xlx833.mydns.jp|Japan
XLX834|xlx834.mydns.jp|Japan
XLX835|wmrasystem.com|United States
XLX836|xlx.n7mky.com|United States
XLX838|185.166.212.132|Canary Islands
XLX839|xlx839.dyndns.org|United States
XLX840|xlx.gb3oa.org.uk|GB
XLX841|dvref.duckdns.org|Korea
XLX844|dv.afu.rwth-aachen.de|Germany
XLX845|xlx845.pota.review|United States
XLX847|xlx847.kk7mnz.com|United States
XLX850|xlx850.bm262.de|Germany
XLX858|xlx-host.top|United States
XLX860|24.134.86.93|Germany
XLX861|noradio86.ddns.net|FR
XLX862|it9bfb.ns0.it|Italy
XLX867|70.8.147.24|United States
XLX870|xlx870.nl|Netherlands
XLX876|xlxd.bh1ofp.com|China
XLX878|xrf878.xreflector-jp.org|Japan
XLX880|dashboard.on6uhf.com|Belgium
XLX883|153.127.25.123|Tokushima Japan
XLX885|xlx885.freeddns.it|Italy
XLX886|xlx886.metropit.net|Taiwan
XLX888|un1eak.svx03.kz|Kazakhstan
XLX892|urf892.cidcomm.com|United States
XLX893|893.pgw.jp|Japan
XLX895|xlx895.laukas.lt|United States
XLX897|xlx897.space|RF
XLX898|xlx.on7hh.be|Belgium
XLX900|xlx.kamenitza.org|Bulgaria
XLX901|urcat-xlx2.ddns.net|CATALUNYA
XLX902|reflector.miodek.me|Germany
XLX904|xrf904.xreflector-jp.org|Japan
XLX905|xlx905.oevsv.at|Austria
XLX909|xlx909.freeddns.org|Thailand
XLX910|xlx910.mywire.org|United States
XLX911|xlx911.patrweb.com|Thailand
XLX912|80.211.1.143|SPAIN
XLX913|xlx913.lmarc.net|United States
XLX914|47.156.44.132|World Wide
XLX916|myxlxw9gae.duckdns.org|United States
XLX917|xlx917.ddns.net|United States
XLX918|xlx918.180152.xyz|Thailand
XLX919|xlx919.freeddns.org|Thailand
XLX920|xlx.bruenderman.org|United States
XLX921|urf001.cumbriacq.com|CUMBRIA UK
XLX922|www.mb6er.com|United Kingdom
XLX923|urf923.lmarc.net|United States
XLX925|xlx925.hopto.org|GB
XLX927|k2as-ref.xyz|United States
XLX928|xlx928.ni2c.us|United States
XLX929|xlx929.vu2jjj.in|India
XLX930|89.46.70.60|Italy
XLX931|172.236.106.40|United States
XLX932|79.58.178.135|Italy
XLX933|xlx933.hamdigital.fr|France
XLX934|xlx934.arifvg.it|Italy
XLX935|xlx.n6lka.com|United States
XLX936|ysf.iu1olu.it|ITALY
XLX937|xlx.rc3c.ru|Russia
XLX938|g3brg.freeddns.org|United Kingdom
XLX939|relay.zaledia.com|Switzerland
XLX940|xlx940.vk2ym.com.au|Australia
XLX942|xlx942.ntsy.me|United Kingdom
XLX943|reflector.va3pdg.ca|Canada
XLX944|xrf944.xreflector-jp.org|Japan
XLX945|xlx945.freeddns.org|United States
XLX947|w8lrk-xlx947.ddnsfree.com|United States
XLX948|dashboard.icqpodcast.com|United Kingdom
XLX949|xlx949.isa-geek.com|United States
XLX950|xlx950.epf.lu|Luxembourg
XLX951|qnet.k4yrn.com|United States
XLX953|142.167.31.8|Canada
XLX956|xlx.dr4w.de|Germany
XLX957|87.106.196.53|Italy
XLX959|xrf959.xreflector-jp.org|Japan
XLX960|xlxlist.dyndns.org|Murphys, Ca. USA
XLX963|www.w5yiu.com|United States
XLX965|xlx965.hblink.it|Italy
XLX968|xlx.jlnet.net|United States
XLX969|urf.k0cks.com|United States
XLX975|w8lrk-xlx975.duckdns.org|United States
XLX976|xlx976.f8kgk.fr|France
XLX977|xlx.nwrg.org.uk|GB
XLX978|xlx978.dyndns.org|United States
XLX979|n5rwk.duckdns.org|United States
XLX980|hamradionyc.com|United States
XLX981|curiously-upward-pegasus.ngrok-free.app|United States
XLX982|w8lrk.dnsalias.org|United States
XLX983|XLX983.K8JTK.org|United States
XLX984|xlx984.hamradio.services|Denver, CO, USA
XLX985|xlx985.pa7ey.nl|Netherlands
XLX986|xlx986.thueringen.link|Germany
XLX987|xlx987.asuscomm.com|California USA
XLX988|xrf988.xreflector-jp.org|Japan
XLX989|xlx989.duckdns.org|United States
XLX990|xlx990.sapotech.com|Japan
XLX991|217.77.14.42|United Kingdom
XLX992|xlx992.2x2online.net|SPAIN
XLX993|fredarc-xlx.duckdns.org|United States
XLX994|urf994.ddns.net|United Kingdom
XLX997|xlx997.iw2gob.it|Italy
XLX998|82.165.6.239|United Kingdom
XLX999|94.177.204.159|Italy
XLXA51|xlx.hamonsite.com|USA - North MS
XLXA57|xrfa57.ddns.net|United States
XLXABL|xlxabl.duckdns.org|Germany
XLXACP|xlxacp.zukamore.co.za|South Africa
XLXARG|xlxarg.xlxreflector.org|USA - Florida
XLXAVM|xlx.km7beo.us|US - Washington
XLXBAS|xlxbas.dyndns.org|Italy
XLXBAT|82.85.236.36|ITALY
XLXBFN|xlxbfn.whitehat-security.org|United State
XLXBMW|xlxbmw.aga.waw.pl|Poland
XLXBOR|xlxbor.ddns.net|Netherlands
XLXBRA|xlxbra.net|Brazil
XLXBSL|xlxbsl.radioamateur.ca|Canada
XLXCAN|198.98.55.19|Canada
XLXCEL|urfcel-dashboard.funknetz-celle.de|Germany
XLXCHA|fzxq.x3322.net|CHINA
XLXCKG|tg46023.cn|China
XLXCMC|iz5cmc.hopto.org|Italy
XLXCNP|xlx.arsacnp.eu|SPAIN
XLXCOD|xlxcod.com|United Kingdom
XLXCOW|xlxcow.nh6fu.com|United States
XLXCZE|jedi.ok2it.com|Czech_Republic
XLXCZS|128.0.182.6|Czechia
XLXD51|xlxd51.ddns.net|Greece
XLXDAM|digital-america.org|United States
XLXDEU|ysf-deutschland.de|Germany
XLXDF8|xlx.df8mr.net|Germany
XLXDIG|urf.w3lby.com|United States
XLXDLN|xlx.radiorabbit.ca|Canada
XLXE2H|e2hub.vra.or.th|THAILAND
XLXE51|192.227.177.16|Greece
XLXEAR|gb7wy.co.uk|United Kingdom
XLXEMB|xlx.bugsbgone.au|Australia
XLXEMI|ik4nzd.ns0.it|ITALY
XLXEMO|217.160.38.80|ITALY
XLXEND|xlxend.mywire.org|Germany
XLXEUS|eus.ham-radio-op.net|Basque Country
XLXFOX|xlxfox.foxhole.radio|United States
XLXFRA|xlxfra.ddns.net|Italy
XLXGBP|xlxgbp.n9muf.org|United States
XLXGOE|87.106.26.8|Germany
XLXGR1|hamsat.eu|Greece
XLXGUN|xrfgun.org|Japan
XLXHAM|xlxham.ircddb.it|Italy
XLXHDH|xlxhdh.ddns.net|Netherlands
XLXHKG|xlxhkg.hkham.net|Hong Kong, China
XLXHRT|xlxhrt.camdvr.org|Germany
XLXHUB|onurbespinar.tplinkdns.com|Türkiye
XLXIDN|101.255.4.222|Indonesia
XLXIGS|xlxigs.fnoy.info|Japan
XLXIHH|ik6ihh.ddns.net|Italy
XLXILS|xlxils.w9ils.org|United States
XLXIS0|xlxis0.is0.org|Sardinia Island
XLXIT1|xlxit1.ircddb.it|ITALY
XLXITA|xlx-ita.dyndns.org|ITALY
XLXITM|urfitm.dyndns.org|ITALY
XLXJAX|jax-beach.hamfm.com|United States
XLXJDV|xlxjdv.freedmr.it|Italy
XLXJET|5.161.215.224|United States
XLXJSS|innet.tplinkdns.com|United States
XLXKHW|xlxkhw.fnoy.info|Japan
XLXKSJ|urfdash.k0eg.radio|United States
XLXLE1|80.211.135.179|Italy
XLXLEF|xlxlef.gb7hh.co.uk|United Kingdom
XLXLWT|xlx.kb7dan.com|United States
XLXMDM|140.83.39.35|Japan
XLXMIL|xlxmil.dk9bt.net|Germany
XLXMLB|xlxmlb.n0oj.net|United States
XLXMMG|xlxmmg.nemmg.club|United States
XLXMYR|xlx.hamsup.my|Malaysia
XLXNFL|xlxnfl.wt0f.com|United States
XLXNLD|dstarnld.pa7lim.nl|Netherlands
XLXNPP|49.232.24.178|China
XLXNRW|do1di.nrw|NRW / Germany
XLXOWG|xlx.m7owg.uk|United Kingdom
XLXPAW|urfpaw.11cats.org|United States
XLXPNW|xlxpnw.duckdns.org|United States
XLXPNY|dstarbrasil.com.br|Brazil
XLXPOL|xlx.minilink.pl|Poland
XLXPRC|120.197.207.2|China
XLXPTA|xlxpta.zs6tvb.xyz|South Africa
XLXQRZ|qrz.cqnet.org|HELLAS Zone Net!
XLXQZX|k9qzx.duckdns.org|United States
XLXRC1|xlxrc1.radiocult.su|Russia
XLXRHR|xlx.remotehamradio.com|USA-NY
XLXRHX|xlxrhx.sq9.online|Poland
XLXRUS|44.32.144.35|RUSSIA
XLXSAT|xlx3.k5wh.net|United States
XLXSCP|xlxscp.iv3scp.it|Italy
XLXSIN|xlx.w9winxlx.us|United States
XLXSOM|45.33.73.221|United States
XLXSP5|xlxsp5.ddns.mobi|Poland
XLXSPB|xlxspb.qth.spb.ru|Russia
XLXSPC|xlxspc.spacecoasttelecom.com|United States
XLXSVD|xlxsvd.duckdns.org|Italy
XLXTEN|xlxten.ddns.net|United States
XLXTEX|xlx.n5hme.net|United States
XLXTNH|tnhams.net|United States
XLXTYL|xlxtyl.itsmith.com|United States
XLXTYO|xrftyo.mydns.jp|Japan
XLXUDN|xrfudn.mydns.jp|Japan
XLXUFB|xlx.ufbnewengland.com|United States
XLXUFO|xlx.ufo.amwan.net|United States
XLXURU|uruguaynet1.2mydns.net|MONTEVIDEO URUGUAY
XLXUS1|xlxus1.w4fe.com|USA - EST
XLXUS2|xlxus2.w4fe.com|USA - CST
XLXUS3|xlxus3.w4fe.com|USA - MST
XLXUS4|xlxus4.w4fe.com|USA - PST
XLXUS5|xlxus5.w4fe.com|USA - Backup
XLXUSA|xlxusa.w4fe.com|United States
XLXUTC|xlxutc.kr0ot.com|United States
XLXUTR|xlx.pi4utr.nl|Netherlands
XLXV69|XLXV69.DDNS.NET|United States
XLXVE1|xlxve1.candx.ca|CANADA-MARITIMES
XLXVE2|xlxve2.candx.ca|CANADA-QC
XLXVE3|xlxve3.candx.ca|CANADA-ONT
XLXVE4|xlxve4.candx.ca|CANADA-MB
XLXVE5|xlxve5.candx.ca|CANADA-SASK
XLXVE6|xlxve6.candx.ca|CANADA-AB
XLXVE7|xlxve7.candx.ca|CANADA-BC
XLXVPS|44.31.15.201|Quebec - Canada
XLXWA1|xlxwa1.kk7okt.net|United States
XLXWDX|xlxwdx.worldwidedx.com|United States
XLXWRN|70.73.135.36|Canada
XLXWSL|213.219.147.227|BELGIUM
XLXXME|deez.vnutz.com|United States
XLXXXX|world.cq-uk.co.uk|United Kingdom
XLXYAI|xlxyai.ja3yai.club|JAPAN
XLXYEG|219.117.204.205|JAPAN
XLXYEK|125.199.48.156|Japan
XLXYKO|xrfyko.mydns.jp|Japan
XLXYLV|xlxylv.ta2kw.keenetic.pro|TÜRKİYE
XLXYO2|xlxyo2.yo2lyn.link|Romania
XLXZVU|176.128.229.6|FR
"""

// swiftlint:enable file_length
