import Foundation

// MARK: - XLXReflector

// Data file: the bundled reflector snapshot dominates the line count.
// swiftlint:disable file_length

struct XLXReflector: Identifiable {
    let name: String
    let host: String
    let ipAddress: String
    let country: String

    var id: String {
        name
    }
}

// MARK: - XLXDirectory

/// Bundled snapshot of the live XLX registry (xlxapi.rlx.lu), reflectors
/// seen within 24h of the snapshot, generated 2026-09-06. Hostnames are
/// the reflector dashboards where they resolve, else the registered IP;
/// the resolved IP (ipAddress) rides along so latency pings need no DNS. Stored as
/// data rather than 800+ struct literals to keep compiles fast.
enum XLXDirectory {
    static let all: [XLXReflector] = xlxRawDirectory.split(separator: "\n").compactMap { line in
        let parts = line.split(separator: "|", omittingEmptySubsequences: false)
        guard parts.count == 4 else {
            return nil
        }
        return XLXReflector(name: String(parts[0]), host: String(parts[1]),
                            ipAddress: String(parts[2]), country: String(parts[3]))
    }

    static func reflector(forHost host: String) -> XLXReflector? {
        let trimmed = host.trimmingCharacters(in: .whitespaces)
        return all.first { $0.host == trimmed }
    }
}

private let xlxRawDirectory = """
XLX000|xlx000.dmr.net.br|201.62.48.60|Brazil
XLX001|217.154.120.107|217.154.120.107|Italy
XLX002|xlx.capwork.cn|60.167.155.113|China
XLX003|reflektor.koledzyzradia.pl|93.179.193.199|Poland
XLX004|121.43.36.126|121.43.36.126|Taizhou-China
XLX005|xlx005.freedmr.uk|44.31.166.9|United Kingdom
XLX006|xlx006.crigan.us|45.32.89.165|United States
XLX007|dcs007.xreflector.net|44.137.42.27|Netherlands
XLX008|xlx.py1ip.com|179.210.38.33|Brazil
XLX009|www.hamtalk.net|118.150.164.96|Taiwan
XLX00A|94.177.201.198|94.177.201.198|Italy
XLX00B|xlx00b.mydns.jp|223.223.44.243|Japan
XLX010|dcs010.xreflector.net|85.197.129.86|Sweden
XLX011|dcs011.xreflector.net|81.95.126.168|Belgium
XLX012|xlx012.ddns.net|192.109.241.46|Poland
XLX013|xlx.bigvortex.com|18.188.189.124|United States
XLX014|dcs014.xreflector.net|52.63.223.130|Australia
XLX015|dcs015.xreflector.net|194.59.205.228|Germany
XLX016|xrf016.xreflector-jp.org|150.66.42.17|Japan
XLX017|31.14.140.141|31.14.140.141|Poland
XLX019|dcs019.xreflector.net|31.7.247.58|Czech Republic and Slovakia
XLX020|xlx020.k2ie.net|66.175.215.217|United States
XLX021|xlx.projekt-pegasus.net|148.251.94.163|Germany
XLX022|xlx022.hamradio.services|144.202.64.224|Denver, CO, USA
XLX023|xlx023.ddns.net|77.85.192.94|Bulgaria
XLX024|xlx024.ddns.net|5.185.11.62|Poland
XLX026|xlx026.net|82.152.175.30|Brazil
XLX027|xlxaras.duckdns.org|185.203.217.7|Italy
XLX028|xlx.k5wh.net|216.128.130.30|United States
XLX029|adk.bigvortex.com|3.129.150.138|United States
XLX030|xlx030.ardv.at|185.230.132.103|Austria
XLX031|xlx.pistar.eu|81.7.13.245|Germany
XLX032|xlx032.epf.lu|158.64.26.140|Luxembourg
XLX033|xlx033.hamdigital.fr|164.132.230.151|France
XLX034|ag5aa.com|155.138.252.203|United States
XLX035|xrf035.wa7dre.org|45.79.94.184|Spokane, WA, USA
XLX036|xlx036.zacharewicz.info|46.170.105.5|Poland
XLX037|xlx037.ddns.net|198.100.154.155|United States
XLX038|xlx038.dyndns.org|44.15.64.56|United States
XLX039|xlx039.dyndns.org|99.79.36.196|United States
XLX040|xlx040.dstar-portugal.pt|185.11.166.85|Portugal
XLX041|206.81.1.250|206.81.1.250|Puerto Rico
XLX042|de9956.ddns.net|81.131.214.206|GB-Wales
XLX043|xlx043.pauldingares.com|147.182.219.238|USA-Georgia
XLX044|xlx044.qsos.uk|77.68.4.213|United Kingdom
XLX045|urf045.pennlinkgroup.com|70.44.20.24|United States
XLX046|xlxchile.radioaficion.pro|104.21.55.220|CHILE
XLX047|202.171.147.58|202.171.147.58|JAPAN
XLX048|xurev.ddns.net|37.15.125.134|Spain
XLX049|xlx049.dyndns.org|54.237.10.173|United States
XLX050|xlx050.bsdworld.org|140.82.51.26|United States
XLX051|2141.adn.systems|84.127.123.185|SPAIN
XLX052|xrf052.xreflector-jp.org|128.22.149.69|Japan
XLX053|xlx053-n0mis.ddns.net|172.233.149.75|United States
XLX054|xlx054.ddns.net|31.62.63.242|Poland
XLX055|52.80.4.154|52.80.4.154|China
XLX056|66.42.126.197|66.42.126.197|United States
XLX057|212.107.141.130|212.107.141.130|Sweden
XLX058|xrf058.xreflector-jp.org|150.66.16.176|Japan
XLX059|dstar.ridigitallink.net|185.169.253.175|United States
XLX060|45.76.133.116|45.76.133.116|United Kingdom
XLX061|xlx.bridge.oarc.uk|192.248.160.49|United Kingdom
XLX062|xlx.superlink.qsl.br|191.252.220.82|Brazil
XLX063|manfred-lichtenstern.de|85.215.161.24|Germany
XLX064|xrf064.owari.biz|122.222.1.50|Aichi Japan
XLX065|xlx.ustriplenickel.com|24.166.245.204|United States
XLX066|209.141.44.203|209.141.44.203|Shandong, China
XLX067|xlx067.duckdns.org|144.202.30.59|United States
XLX068|xlx068.ircddb.it|212.237.22.199|Italy
XLX069|grupoelite.es|51.77.213.200|Spain
XLX070|xlx.dstar.com.br|186.193.221.178|Brazil
XLX071|xrf.elechomebrew.com|211.60.41.185|Daegu, South Korea
XLX072|xlx.m0ned.org|217.154.56.214|United Kingdom
XLX073|xlx073.wiredham.org|45.77.192.120|United States
XLX074|xlx074.bh1nyr.net|149.104.31.72|Beijing, China
XLX075|xlx.flg-wiresx.cloud|82.180.133.125|United States
XLX076|xrf076.xreflector-jp.org|203.137.116.117|Japan
XLX077|xe1dvi.crabdance.com|85.8.149.218|USA-MEX
XLX078|xlx.bh4crv.com|139.196.158.18|China
XLX080|xrf080.mydns.jp|121.81.85.6|Japan
XLX081|xrf081.mydns.jp|59.190.22.105|Japan
XLX082|xlx082.hamradio.services|44.20.29.130|Denver, CO, USA
XLX083|www.cl-link.cl|200.1.123.75|CHILE
XLX084|xlx.dn2ane.de|74.208.132.51|Germany
XLX085|xrf085.mydns.jp|113.150.26.8|Japan
XLX086|140.179.13.243|140.179.13.243|China
XLX087|ballarat-australia.net|172.236.53.203|Ballarat - Australia
XLX088|xlx088.pa4tw.nl|44.137.37.242|Netherlands
XLX089|xlx089.newenglanddigitalradio.com|155.138.240.150|United States
XLX090|kurpie.ddns.net|51.83.186.28|Poland
XLX091|217.142.144.62|217.142.144.62|China
XLX092|xlx092.duckdns.org|80.211.239.166|Schweiz
XLX093|famiuse.ddns.net|81.57.30.58|Italy
XLX094|xlx.utahdrn.org|143.198.79.122|United States
XLX095|xrf095.xreflector-jp.org|128.22.171.138|Japan
XLX096|096busan.duckdns.org|121.145.136.53|KOREA
XLX097|xlx097.newenglanddigitalradio.com|207.246.112.46|United States
XLX098|xrf098.mydns.jp|125.198.85.43|Nagoya JAPAN
XLX099|vmi2909834.contaboserver.net|62.84.187.1|Hungary
XLX100|d-star.lt|85.255.60.41|Lithuania
XLX101|xlx.lt|78.57.213.168|Lithuania
XLX102|xlx102.xlxreflector.org|47.206.136.220|USA - Florida
XLX103|xlx103.xlxreflector.org|47.206.136.221|Canada
XLX104|xlx104.xlxreflector.org|47.206.136.222|USA - Georgia
XLX105|ref105.dstar.com.br|193.202.85.87|Brazil
XLX106|urf106.com|24.127.204.177|United States
XLX108|suzaka.f5.si|126.116.54.195|Japan
XLX109|d-star.f5.si|118.27.15.122|Japan
XLX110|140.82.14.24|140.82.14.24|United States
XLX111|xrf111.xreflector-jp.org|61.195.96.160|Japan
XLX112|xlx.jayceera.in|108.61.205.188|United States
XLX113|xlx.foerdefunk.de|87.106.240.185|Germany
XLX114|xlx114.duckdns.org|185.225.122.49|Finland
XLX115|xlx115.hb9vd.ch|217.182.128.3|Switzerland
XLX116|xlx116.cisaragrigento.it|80.211.79.156|Italy
XLX117|xlx117.ddns.net|200.108.249.62|Uruguay
XLX119|xlx119.duckdns.org|140.82.61.52|Greece
XLX120|xlx120.com|15.204.232.22|United States
XLX121|xlx121.ddns.net|79.51.202.50|Italy
XLX122|194.37.80.40|194.37.80.40|Greece
XLX123|xlx.home64.de|217.160.53.97|Germany
XLX125|79.172.213.236|79.172.213.236|Hungary
XLX126|jrlinden.zapto.org|172.56.221.3|United States
XLX127|xlx127.ddns.net|88.16.138.100|SPAIN
XLX128|xlx128.radiohub.ar|104.21.84.227|Argentina
XLX129|xlx129.comfusion.co.nz|203.86.196.15|New Zealand
XLX130|xlx130.nh6fu.com|44.27.34.238|United States
XLX131|xlx131.pe1er.nl|45.80.171.194|Netherlands
XLX132|xlx132.dstar.radom.pl|195.225.77.3|Poland
XLX133|xlx133.ddns.net|92.16.181.229|United Kingdom
XLX134|xlx134.ddns.net|51.83.134.240|Poland
XLX135|xlx.hopto.org|45.92.44.246|United Kingdom
XLX136|xlx136.f5.si|153.221.126.151|Kanazawa Japan
XLX137|xlx137.mywire.org|78.138.0.61|United States
XLX138|xlx138.freeddns.org|103.195.7.20|Thailand
XLX139|xlx139.dyndns.org|35.182.55.222|United States
XLX140|xlx140.nix.pt|95.211.211.145|Europe
XLX141|xlx.vadigital.network|3.19.122.217|United States
XLX142|xlx.k7jsx.net|172.67.218.209|United States
XLX143|xlx143.duckdns.org|82.88.127.168|Italy
XLX145|URF145.pennlinkgroup.com|70.44.15.176|United States
XLX146|131.186.42.239|131.186.42.239|Japan
XLX147|G4SKM.duckdns.org|90.220.164.137|United Kingdom
XLX148|xlx.hs3tdi.com|122.154.141.51|Thailand
XLX149|xlx.pwk.ac.th|122.154.140.136|Thailand
XLX150|xlx150.ddns.net|192.241.158.197|United States
XLX151|xlx151.hamonsite.com|159.203.105.64|USA - North MS
XLX152|kj4dhf.ddns.net|130.45.226.194|United States
XLX153|xlx153.dyndns.org|15.222.4.216|United States
XLX155|thedive155.com|104.21.34.234|TheDive USA
XLX157|xlx157.dyndns.org|195.231.78.164|Italy
XLX158|d-star2.f5.si|114.178.84.228|Japan
XLX159|xlx159.whiskey7.site|172.67.191.17|Olympia, Washington USA
XLX160|xrf160.xreflector-jp.org|61.195.109.179|Japan
XLX161|xlx161.eu|138.2.175.34|Republic of BULGARIA
XLX162|44.32.81.27|44.32.81.27|Thailand
XLX163|45.143.93.75|45.143.93.75|Samara
XLX164|reflector.k4fsg.net|44.98.254.88|United States
XLX165|XLX165.ddns.net|84.254.24.85|Greece
XLX166|79.137.85.89|79.137.85.89|Italy
XLX167|XLX167-n0mis.ddns.net|172.233.157.125|United States
XLX168|xlx168.mydns.jp|180.44.173.248|Japan
XLX169|xlx169.26269.de|217.72.202.215|Germany
XLX170|xlx170.hamoverip.com|64.23.194.143|United States
XLX171|xlx.r3pij.ru|62.113.103.244|Russia
XLX172|jm1fvo.mydns.jp|27.91.233.142|Japan
XLX173|xlx.lagranderadioclub.com|137.184.146.29|United States
XLX174|xlx.digitalfunk-nordost.de|81.169.128.244|Germany
XLX176|xrf176.xreflector-jp.org|128.22.152.69|Japan
XLX177|xlx.iz3mez.it|85.215.153.178|Italy
XLX178|xlx.buxton.radio|80.229.161.124|Buxton, GB
XLX179|atzxlx.ddns.net|31.48.22.144|NE Wales
XLX180|xlx180.warn.org|192.241.240.7|Ohio USA
XLX181|ny1usxlx.ddns.net|64.177.41.242|United States
XLX182|dvmq.ddnsfree.com|168.107.6.135|Korea
XLX184|sq5buj.pl|83.238.162.244|Poland
XLX185|xlx185.hamradio.onl|64.181.204.84|United States
XLX187|multinode.fupcinternational.com|24.94.6.105|United States
XLX188|xlx.bitbybithams.com|152.86.246.81|United States
XLX189|46.181.171.44|46.181.171.44|Россия
XLX190|xlx.argentinaroom.com.ar|186.123.100.105|Argentina
XLX191|cqlaplata.ddns.net|181.23.120.136|Argentina
XLX192|jg5eqv.mydns.jp|118.27.9.127|Japan
XLX194|xlx.smslowianin.pl|178.238.240.209|POLAND
XLX195|134.122.12.176|134.122.12.176|United States
XLX196|xlx196.dyndns.org|40.233.100.29|Canada
XLX197|xlx197.dyndns.org|141.148.160.12|Canada
XLX198|xlx198.ddns.net|190.97.6.106|Argentina
XLX199|xlx.argentinanetwork.ar|64.176.17.106|ARGENTINA
XLX200|ec2ut.ddns.net|88.6.132.118|Spain
XLX201|xlx201.amgcloud.es|88.5.111.0|SPAIN
XLX202|xlx202.clickandhope.com|130.162.162.192|United Kingdom
XLX203|50.116.36.65|50.116.36.65|United States
XLX204|xlx204.ddns.net|77.162.87.115|Netherlands
XLX205|www.raw.usk4lls.com|134.199.240.200|United States
XLX206|44.31.191.62|44.31.191.62|Ireland
XLX207|dash-xlx207.duckdns.org|81.137.250.131|Bedford United Kingdom
XLX208|xlx208.f5kav.fr|213.186.34.50|France
XLX209|xlx.smokyshare.com|104.171.252.88|United States
XLX210|adn2061.be|173.212.223.187|Belgium
XLX211|xlx211.radio-nw.net|81.33.45.135|Spain
XLX212|xlx212.dstar.club|52.38.90.188|United States
XLX213|xlx.wp4ssb.net|207.246.72.25|Puerto Rico
XLX214|xlx214.xreflector.es|212.227.87.198|ES
XLX215|hadars-reflector.ddns.net|46.101.80.121|United Kingdom
XLX216|xlx216.n8usk.com|172.234.217.149|United States
XLX217|xlx217.dynamic-dns.net|100.36.101.23|United States
XLX218|xlx218.chaverimradio.com|138.128.247.74|United States
XLX219|108.61.87.174|108.61.87.174|United States
XLX220|xlx220.sapotech.com|164.70.120.126|Miyazaki Japan
XLX221|xrf221.dyndns.org|44.15.64.57|United States
XLX222|172.233.145.145|172.233.145.145|Bahrain
XLX223|44.27.136.19|44.27.136.19|United States
XLX225|xrf225.xreflector-jp.org|61.195.108.252|Japan
XLX226|44.32.81.143|44.32.81.143|Thailand
XLX227|xlx227.hamnet.ro|89.33.44.100|Romania
XLX228|XLX228.myddns.me|174.179.188.206|United States
XLX229|dstar.hamnet.xyz|195.49.75.204|Switzerland
XLX230|xlx230.ok2it.com|80.250.3.114|Czech Republic
XLX231|xlx.is0.org|94.32.71.16|Sardinia Island
XLX232|rudinet.giize.com|82.59.234.147|Italy
XLX233|g7usp.interadd.co.uk|217.160.0.104|United Kingdom
XLX234|82.165.7.197|82.165.7.197|United Kingdom
XLX235|ddmtc.ddns.net|146.199.249.4|United Kingdom
XLX236|xlx236.jdlspeedy.us|54.161.39.228|United States
XLX237|xlx237.eastcoastreflector.com|74.196.158.133|United States
XLX238|xlx238.d-star4all.dk|46.32.62.49|Denmark
XLX239|reflector.kb2idx.com|216.225.197.186|United States
XLX240|xlx.hb9v.ch|83.228.212.233|Switzerland
XLX241|xlxrem.xreflector.es|51.83.98.154|Spain
XLX242|66.42.84.85|66.42.84.85|United Kingdom
XLX243|soky.online|107.172.243.188|United States
XLX244|xlx.rz44.com|72.14.187.79|United States
XLX245|xlx245.sub.h-sol.jp|153.218.133.190|Japan
XLX246|xlx.mkagawa.com|172.93.48.159|N California, USA
XLX247|xlx.oz-dmr.network|44.31.91.236|United Kingdom
XLX248|xlx248.freestar.network|81.136.218.49|United Kingdom
XLX250|xlx.n5bdj.com|23.130.172.11|United States
XLX251|xlx251.ddns.net|195.201.35.61|Greece
XLX252|xlx252.ddns.net|51.195.107.129|Greece
XLX254|xlx254.ki5kzu.net|198.58.115.22|United States
XLX255|xrf255.reflector.up4dar.de|142.91.158.199|Ukraine
XLX256|xrf256.swl.in.ua|178.136.97.107|Ukraine
XLX257|xlxd257.uw0wu.com|45.89.91.89|Ukraine
XLX258|ref258.ddns.net|75.137.209.136|United States
XLX259|xlx.olympy.org.ua|178.63.41.205|Ukraine
XLX260|xlx.do9ck.de|213.178.70.236|Germany
XLX262|xlx.prgm.org|217.88.23.211|Germany
XLX263|xlx.afu-kiel.de|217.160.26.79|Germany
XLX264|52.2.131.118|52.2.131.118|United States
XLX265|xlx.n8mfn.club|74.132.44.239|United States
XLX266|aderdigitales.ddns.net|62.171.178.202|Spain
XLX267|xlx.ct1ebq.com|91.209.16.180|Portugal
XLX268|xlx268.from-ct.com|185.11.166.22|Portugal
XLX269|urf269.db0htv.de|44.31.0.6|Germany
XLX270|xlx270.epf.lu|158.64.26.132|Luxembourg
XLX271|xlx271.ddnss.org|212.227.96.27|Germany
XLX272|xlxd.9y4c.com|172.233.149.106|Trinidad and Tobago
XLX273|vk3agk.net.au|172.236.34.49|AU
XLX275|xlx275.superlink.qsl.br|191.252.220.100|Brazil
XLX277|xlx277.bitbybithams.com|67.207.37.195|United States
XLX279|xlx.jl-networking.co.uk|212.71.250.63|United Kingdom
XLX280|iz8izj.ddns.net|87.1.117.110|Italy
XLX281|xlx.kd7lmn.com|74.91.126.68|United States
XLX282|xlx282.orangesun.org|172.67.178.60|United Kingdom
XLX283|xlx283.mydns.jp|92.202.87.97|JAPAN
XLX284|dmrbulgaria.net|185.80.0.95|Bulgaria
XLX285|457430.ip.hamvoip.org|24.95.64.116|United States
XLX286|xlx286.dmrturkiye.com|93.186.113.147|TÜRKiYE
XLX288|ic8uoh.ddns.net|79.52.136.35|Italy
XLX290|ct7apz.zapto.org|188.81.134.99|Portugal
XLX291|xrf291.xreflector-jp.org|101.143.242.189|Japan
XLX294|xlx.dmr.net.mk|84.74.145.32|Macedonia
XLX295|xlx295.dyndns.org|74.208.48.179|United States
XLX296|xlx296.h-sol.jp|153.127.50.48|Japan
XLX298|xrf298.mydns.jp|122.132.48.86|NAGOYA JAPAN
XLX299|www.xlx299.nz|202.36.45.107|New Zealand
XLX300|xlx300.net|45.159.173.18|Brazil
XLX301|xlx301.stagecraft.cx|44.32.9.156|Australia
XLX302|xlx.vk2cjr.au|172.67.207.251|Australia
XLX303|coloradodigital.duckdns.org|98.38.29.7|United States
XLX304|304.ve5aas.ca|139.177.194.71|Canada
XLX305|xlx.m5adi.com|141.95.229.116|Manchester, UK
XLX306|urf306.warg.org.au|103.1.187.251|Australia
XLX307|xlx307.ddns.net|72.21.76.154|United States
XLX308|coloradu.co|45.56.124.18|United States
XLX309|xlx.ke4tzn.com|198.74.54.133|United States
XLX310|srv.ysf-france.fr|51.38.82.109|FR YSF France
XLX311|ernix.de|93.211.196.43|Germany
XLX312|xlx.dmr-marc.net|192.241.160.183|United States
XLX313|94.177.160.244|94.177.160.244|Italy
XLX314|xlx314.ddns.net|181.97.180.157|Argentina
XLX317|xlx317.duckdns.org|45.63.77.236|United States
XLX318|xlx.kn6rbp.com|47.181.192.143|United States
XLX319|92.62.226.78|92.62.226.78|Czechia
XLX320|ea4grr.ddns.net|81.43.0.166|EXTREMADURA
XLX321|xlxd.net.drc.bz|185.144.73.93|Italy
XLX322|76.219.234.40|76.219.234.40|United States
XLX323|xlx323.ddns.net|57.135.192.137|United States
XLX324|192.253.246.36|192.253.246.36|United States
XLX325|xlx325.nt1k.com|168.235.80.185|United States
XLX326|xrf326.xreflector-jp.org|61.195.125.193|Japan
XLX327|xlx327.from-ak.com|104.238.156.182|United States
XLX328|212.237.33.114|212.237.33.114|Switzerland
XLX329|xrf329.aa0.netvolante.jp|125.202.138.7|Japan
XLX330|xlx.n8ei.com|23.129.32.82|United States
XLX331|64.237.214.46|64.237.214.46|Coamo PR
XLX332|xlx332.ddns.net|188.213.168.99|Italia - Puglia - Lecce - Squinzano
XLX333|xlx333.bvc.pl|46.149.220.118|Poland
XLX334|alabamalink.info|199.119.98.171|United States
XLX335|xlx.hamfusion.com|144.202.61.208|United States
XLX337|multi.kc5jmj.com|104.251.219.231|United States
XLX339|xlx339.de|87.106.165.159|Germany
XLX340|prboriken.ddns.net|129.213.183.116|Puerto Rico
XLX342|xlx342.websdr-ea1url.es|217.160.228.154|Spain
XLX344|k6egg.hamradio.one|96.126.100.128|United States
XLX345|xlx345.pb1sam.nl|212.114.109.209|Netherlands
XLX346|xrf346.xreflector-jp.org|128.22.135.35|Japan
XLX347|xlx.kq4afy.radio|74.207.235.23|Florida USA
XLX349|xlx.poa.nyc|67.85.61.239|United States
XLX350|xlx350.f5.si|153.227.87.133|Kanazawa Japan
XLX351|xlx351.dyndns.org|15.156.176.95|United States
XLX352|xlx352.duckdns.net|64.190.63.222|United States
XLX353|xlx353.ei3rcw.ampr.org|44.155.254.12|Ireland
XLX354|xlx354.qsos.uk|77.68.4.213|United Kingdom
XLX355|223.95.197.217|223.95.197.217|China
XLX356|zlatix.com|217.174.61.117|Bulgaria
XLX357|xlx357.arrg.club|165.232.144.212|your_country
XLX358|xlx358.signalsphere.org|45.79.211.141|United States
XLX359|xlx359.com|94.156.172.213|Bulgaria
XLX360|360.unifiedradios.com|45.56.120.48|United States
XLX361|manjello.com|144.202.24.194|United States
XLX363|urf363.merg.biz|212.88.159.19|Germany
XLX364|xlx364.n1xrs.net|172.67.188.106|United States
XLX365|xlx365.ddns.net|46.12.28.103|GREECE
XLX369|72.89.122.8|72.89.122.8|United States
XLX370|xlx370.selfip.com|188.213.168.24|Italy
XLX371|xlx371.selfip.com|77.81.230.11|Italy
XLX372|xlx372.kf0lpt.com|64.23.164.123|United States
XLX373|xrf373.mydns.jp|121.85.180.173|Kyoto Japan
XLX374|xlx.9z4rg.com|68.183.19.139|Trinidad and Tobago - REACT
XLX375|xlx375.bfrr.by|86.57.150.4|Belarus
XLX376|xlx376.nikolabs.net|172.67.172.240|Murica!-zl
XLX377|xlx.toytron.com|186.159.96.100|Curacao
XLX379|nfoxlxnorcal.dyndns.org|74.91.117.153|Murphys, Ca. USA
XLX380|xlx380.repeatme.ca|104.21.21.61|Canada
XLX381|xlx.trianglenc.net|74.91.114.100|United States
XLX384|xlx.MRN.mywire.org|162.216.242.206|United States
XLX385|xlx.mrn2.mywire.org|162.216.242.206|United States
XLX386|xlx.foxhole.radio|52.176.210.10|United States
XLX387|xlx.rkelzas.ba|209.250.237.53|Bosnia & Herzegovina
XLX388|xlx.alecwasserman.com|207.246.105.178|United States
XLX390|xlx390.ddns.net|79.27.179.108|Italy
XLX393|xrf393.mydns.jp|219.111.16.62|JAPAN
XLX394|xlx394.ddns.net|80.201.168.212|Nicolas ON4VK
XLX395|xlx395.grupporadiofirenze.net|95.255.196.50|Italy
XLX396|xlx.lattuga.org|96.44.137.162|United States
XLX397|64.121.36.162|64.121.36.162|United States
XLX398|k4ern.net|45.79.216.134|United States
XLX400|pp5au.net|92.246.128.105|Brazil
XLX401|pankoe.no-ip.biz|98.115.177.115|United States
XLX402|synoweb.ddns.net|91.86.232.96|Flémalle
XLX403|xlx403.qsl.me|44.32.224.45|CANADA
XLX404|xlx.bendiksverden.net|195.35.109.55|Norway
XLX405|xlx405.repeatme.ca|172.67.196.201|Canada
XLX406|xlx406.ddns.me|69.48.207.70|United States
XLX407|n7wwl.ddns.net|208.191.21.181|United States
XLX408|xlx408.ddns.me|74.208.69.215|Philippines
XLX409|w6tnt.com|173.255.221.199|United States
XLX410|qrz.com|23.23.229.197|United States
XLX411|socaldigitalk.com|172.233.138.81|United States
XLX412|xrf412.xreflector-jp.org|202.218.34.165|Japan
XLX413|xlx413.mydns.bz|14.3.218.21|Japan
XLX414|xlx.iq3gdb.net|185.170.138.30|Italy
XLX415|kj6vrc.com|104.200.25.29|United States
XLX416|xlx416.repeatme.ca|172.67.196.201|Canada
XLX417|xlx417.repeatme.ca|172.67.196.201|Canada
XLX418|xlxd.petitpingouin.org|138.197.136.190|Canada
XLX419|xlx419.dyndns.org|15.223.207.151|United States
XLX420|xlx.ve2sus.com|104.21.30.162|Canada
XLX421|dl-nordwest.com|152.53.85.93|Germany
XLX422|xlx422.lu9hoo.com.ar|181.87.245.210|Argentina
XLX423|44.27.137.39|44.27.137.39|United States
XLX424|gpj-hamradio.servebeer.com|31.32.149.4|La Haye Centre France
XLX425|xlx.rfelettronica.com|31.14.136.200|Italy
XLX426|xlx-mx.ddns.net|142.44.211.133|Mexico
XLX427|xlx427.repeatme.ca|172.67.196.201|Canada
XLX429|66.154.114.23|66.154.114.23|Managua, Nicaragua
XLX42D|xlx42d.dyndns.org|90.38.208.150|france
XLX430|xlx430.mydns.jp|27.93.24.171|Japan
XLX431|xrf431.xreflector-jp.org|61.195.98.225|Japan
XLX432|xlx.vkradio.com|112.213.34.65|Australia
XLX433|217.160.121.75|217.160.121.75|Germany
XLX434|107.152.38.36|107.152.38.36|SPAIN
XLX435|xlx435.unusualperson.com|76.87.10.176|United States
XLX437|109.172.7.162|109.172.7.162|your_country
XLX438|tonaru.net|121.86.200.125|JAPAN
XLX439|italyi4multip.ddns.net|79.55.240.188|Italy
XLX440|xrf440.e-kyushu.net|218.251.80.22|Japan
XLX441|xrf441.xreflector-jp.org|203.137.99.110|Japan
XLX442|xlx.k1dbc.com|71.218.102.221|United States
XLX443|xlx443.dd8ba.com|185.248.150.137|Germany
XLX444|51.83.46.75|51.83.46.75|Netherlands
XLX445|xrf445.dynu.net|18.221.229.191|United States
XLX446|xrf446.dynu.net|24.166.220.247|United States
XLX447|xlx447.radiorubka.org|80.249.145.99|Apatity
XLX448|xlx.wa9hxl.com|66.206.60.59|Wisconsin, USA
XLX449|cw.ossdr.com|64.176.217.153|United States
XLX450|casaos.dvham.com|220.71.19.9|Korea
XLX451|xlx.dl3mc.de|185.14.13.16|NRW / Germany
XLX452|194.87.210.74|194.87.210.74|Murman
XLX453|61.239.171.240|61.239.171.240|Hong Kong, China
XLX454|xlx454.hkham.net|218.103.102.5|Hong Kong, China
XLX455|hst-new.hst.tu-dortmund.de|129.217.200.4|Germany
XLX456|xlx456.de|54.37.205.183|Germany
XLX457|ysf.kansascitywide.com|76.196.111.155|United States
XLX458|xxlx.w0fh.net|136.35.141.187|United States
XLX459|xrf459.xreflector-jp.org|150.66.16.108|Japan
XLX460|xlx460.duckdns.org|172.234.218.11|United States
XLX462|xlx462.ddns.net|84.97.38.134|France
XLX465|62.109.27.102|62.109.27.102|your_country
XLX467|xlx467.snwlab.net|153.126.179.214|Japan
XLX470|xlxnettalk.dyndns.org|104.153.108.131|Northern Ca. USA
XLX474|xlx474.duckdns.org|34.138.116.246|Poland
XLX475|118.27.35.184|118.27.35.184|Hiroshima JAPAN
XLX476|171.33.84.7|171.33.84.7|France
XLX477|g7rpg.hubnetwork.uk|81.187.19.200|United Kingdom
XLX479|imrs.amcomm.network|172.67.175.135|United States
XLX480|xlx480.edsreflector.com|172.67.168.61|United States
XLX483|xlxcwops.dyndns.org|74.91.117.184|Pine Grove, Ca. USA
XLX484|xlx.reonet.no|212.227.80.36|Norway
XLX485|xlx485.carc-nc.us|65.132.223.230|North Carolina, USA
XLX486|171.33.87.233|171.33.87.233|France
XLX487|31.163.198.165|31.163.198.165|USSR
XLX489|45.77.126.133|45.77.126.133|United States
XLX490|carmarthenars.ddns.net|77.104.180.135|United Kingdom
XLX492|92.118.113.80|92.118.113.80|United States
XLX493|xlx493.w0chp.radio|104.218.221.46|Minn. USA
XLX494|xlx.netasylum.com|162.33.59.40|United States
XLX495|185.255.132.168|185.255.132.168|USSR
XLX497|xlx497.endoria.net|185.10.49.200|Netherlands
XLX500|xlx500.org|45.63.25.110|Australia
XLX501|www.xlx501.xreflector.es|213.186.33.5|El Salvador
XLX502|200.94.250.24|200.94.250.24|Guatemala
XLX503|xlx.kansascitywide.com|76.196.111.156|United States
XLX504|38.7.31.70|38.7.31.70|Honduras
XLX505|vk7hse.duckdns.org|45.248.50.37|Australia
XLX506|126.111.77.170|126.111.77.170|Ehime Japan
XLX507|hp1cdw.ddns.net|190.123.237.11|Panama
XLX508|xlx-owl.de|104.156.136.8|Germany
XLX510|xrf510.xreflector-jp.org|61.195.126.75|Japan
XLX511|xlx511.ddns.net|178.79.110.13|Slovenia
XLX512|xlx512.newcastle-dstar.com|34.209.50.46|United States
XLX514|xrf514.xreflector-jp.org|203.137.118.143|Japan
XLX515|xrf515.xreflector-jp.org|203.137.78.35|Japan
XLX516|xlx.bd4two.site|101.132.21.119|CN
XLX517|xlx517.radiosc.net|67.212.42.234|United States
XLX518|xlx518.n18.de|176.9.1.168|Germany
XLX519|xrf519.ve3zin.com|134.195.88.234|Canada
XLX520|520ref.theworkpc.com|44.32.128.18|United States
XLX522|xlx.lucifernet.com|103.197.58.223|Malaysia
XLX523|edone.lucifernet.com|124.82.136.131|Malaysia
XLX524|xlx.lancs.fm|217.40.112.194|United Kingdom
XLX525|xlx525.webhop.net|74.207.229.113|North Carolina, USA
XLX528|it9frnag.ns0.it|188.213.171.204|Italy
XLX529|80.211.229.187|80.211.229.187|Italy
XLX530|xlx530.hopto.org|34.199.8.144|New Zealand
XLX532|xlx532.oevsv.at|89.185.97.34|Austria
XLX538|xrf538.mydns.jp|131.129.40.179|Osaka Japan
XLX540|74.207.225.205|74.207.225.205|Monterrey Mexico
XLX543|croatia-digital-group.com|161.97.112.218|CROATIA
XLX545|xlx545.pennlinkgroup.com|3.215.215.169|United States
XLX546|71.91.41.20|71.91.41.20|United States
XLX547|130.51.20.196|130.51.20.196|USA - California
XLX548|kb5sj.com|74.208.174.114|United States
XLX551|120.27.213.225|120.27.213.225|China
XLX555|0la8wrdmqv91ywa4.myfritz.net|93.240.83.53|Germany
XLX556|xlx556.kq4tnv.net|108.56.177.81|United States
XLX559|5.249.151.6|5.249.151.6|Poland
XLX560|xrf560.xreflector-jp.org|150.66.42.72|Japan
XLX561|xrf561.xreflector-jp.org|128.22.133.152|Japan
XLX564|8.137.165.149|8.137.165.149|P.R.China'
XLX565|66.42.70.161|66.42.70.161|Canada
XLX567|xlx.suonnet.rs|79.101.0.42|Serbia
XLX568|xlx568.hs8as.com|44.32.82.150|Thailand
XLX569|151.97.13.145|151.97.13.145|Italy
XLX570|xlx.repeater.net|44.27.22.83|United States
XLX573|45.79.218.91|45.79.218.91|United States
XLX575|xlx575.lobo.net|207.251.56.142|United States
XLX576|refleqtion.net|198.58.110.40|United States
XLX578|airport.bitbybithams.com|162.231.21.203|United States
XLX580|xlx580.f5.si|153.227.88.56|Kanazawa Japan
XLX581|xlx581.py2ko.com|195.35.19.189|Brazil
XLX583|xrf583.mydns.jp|211.132.55.138|JAPAN
XLX585|xlx585.net|213.212.133.250|ITALIA IPv4+IPv6+AMPR 44
XLX586|xlx586.ari-rivarolo.org|213.212.132.246|ITALIA IPv4+IPv6
XLX590|xlx590.mydns.jp|163.58.70.135|Japan
XLX595|xlx.xlx595.net|217.160.187.38|Italy
XLX598|dx6cn.duckdns.org|172.237.71.216|PH
XLX599|xrf599.xreflector-jp.org|150.66.25.83|Japan
XLX600|dvsph.net|172.67.214.72|United Kingdom
XLX601|172.234.206.136|172.234.206.136|United States
XLX604|xlx604.jedham.uk|139.162.241.24|United Kingdom
XLX606|87.106.55.42|87.106.55.42|Italy
XLX607|xlx.somberjp.com|104.21.6.75|United States
XLX608|xrf608.xreflector-jp.org|219.122.253.83|Fukuoka Japan
XLX610|reteradio.cisartrieste.it|193.194.17.18|ITALY
XLX613|167.114.144.141|167.114.144.141|Canada
XLX616|xlx616.aivian.org|222.71.150.92|China
XLX618|ysf.kn6rbp.com|47.181.192.142|United States
XLX620|xlx620.starfield.link|61.195.108.241|Japan
XLX621|urf.hrcc.link|15.218.44.59|United States
XLX626|3907.hamradio.one|45.79.222.143|United States
XLX628|xlx628.scumm.it|217.154.180.134|Italy
XLX630|xrf630.xreflector-jp.org|61.195.125.81|Japan
XLX632|xlx632.dstar.corbettdigital.net|64.91.238.36|United States
XLX633|xlx.ke0tcf.radio|74.51.129.179|United States
XLX634|xrf634.xreflector-jp.org|150.66.9.57|Japan
XLX635|xlx.dl4ybg.de|202.61.192.59|Germany
XLX636|xlx.ham.lv|135.181.206.254|Latvia
XLX637|w6idk.com|72.174.162.14|United States
XLX639|xrf639.mydns.jp|49.135.35.146|JAPAN
XLX642|xlx.qsl.lt|212.24.103.170|Lithuania
XLX644|b8fe0a845997.sn.mynetname.net|37.98.194.60|Greece
XLX645|xlx645.pennlinkgroup.com|34.196.134.215|United States
XLX647|hs5blo.fortiddns.com|58.8.190.80|Thailand
XLX649|doghousenet.com|38.59.15.11|United States
XLX654|xrf654.xreflector-jp.org|128.22.131.129|Japan
XLX655|xlx655.ddns.net|146.64.235.19|South Africa
XLX656|173.230.139.250|173.230.139.250|United States
XLX660|xlx660.ddns.net|150.31.163.107|JAPAN
XLX661|jg6yjw.mydns.jp|210.203.214.9|Japan
XLX662|662.duckdns.org|88.231.211.241|United States
XLX665|xrf665.xreflector-jp.org|58.191.43.44|Japan
XLX666|95.179.179.175|95.179.179.175|United Kingdom
XLX667|217.154.116.45|217.154.116.45|Italy
XLX668|urf.n9hxr.radio|99.198.100.8|United States
XLX669|xlx.shadowtronics.org|139.144.253.235|United States
XLX672|xlx672-dash.pistar.uk|104.21.92.112|United Kingdom
XLX673|xrf673.xreflector-jp.org|180.147.243.178|Japan
XLX674|m0unc.co.uk|86.172.47.79|United Kingdom
XLX676|676.n0mb.net|23.155.40.10|United States
XLX678|xlx.m0lxq.com|107.175.36.35|United Kingdom
XLX679|xlx.borris.me|45.79.180.62|United States
XLX680|xlx680.f5.si|153.130.136.236|Kanazawa Japan
XLX683|198.46.160.211|198.46.160.211|United States
XLX687|xlx.digitalradioke4qcm.wiki|50.116.42.52|United States
XLX688|xlx688.ab8m.net|3.89.164.167|United States
XLX689|97.107.128.47|97.107.128.47|United States
XLX693|44.27.131.126|44.27.131.126|United States
XLX697|xlx697.vr2mw.com|1.36.228.157|HONG KONG
XLX698|xrf698.xreflector-jp.org|203.137.123.89|Japan
XLX699|xlx699.se|204.168.251.243|Sweden
XLX700|xlx.pd3rfr.nl|5.254.117.43|Netherlands
XLX701|xrf701.xreflector-jp.org|61.195.107.77|Japan
XLX704|149.28.43.188|149.28.43.188|United States
XLX705|xrf705.xreflector-jp.org|128.22.134.161|Japan
XLX706|xlx706.iz0rin.it|31.14.142.124|Italy
XLX707|dstar.digitalevoice.nl|90.145.156.242|Netherlands
XLX708|xrf708.xreflector-jp.org|150.66.20.222|Japan
XLX710|dstar.pa7lim.nl|94.72.113.36|Netherlands
XLX711|k4zxx.net|155.138.225.38|United States
XLX713|ysf.k0ros.net|172.232.29.215|United States
XLX714|xlx714.radioaficionats.com|87.106.80.210|Catalunya
XLX715|xlx-urcat.ddns.net|92.59.170.78|CATALUNYA
XLX716|xlx716.dmr-peru.net|190.235.220.125|Peru
XLX717|88.159.31.251|88.159.31.251|NL
XLX718|718xlx.ddns.net|136.244.96.172|Italy
XLX719|crsjo.duckdns.org|186.177.160.159|Costa Rica
XLX720|xlx.colorado720.com|66.37.129.198|United States
XLX721|xlx721.dyndns.org|184.56.185.241|United States
XLX722|xlx722.k9chu.com|192.210.200.20|United States
XLX723|xlx723.sv1bgm.net|95.133.192.51|Greece
XLX727|xlx727.gleeze.com|143.198.216.15|Thailand
XLX729|xlx729.huskyno.se|136.243.236.116|United Kingdom
XLX730|sdradio.cl|186.64.123.59|CHILE
XLX732|xlx.octanenetwork.net|149.28.51.5|United States
XLX733|w2bn-xlx.na9x.com|3.130.19.193|United States
XLX734|15.204.230.203|15.204.230.203|Venezuela
XLX735|pr-xlx.k2ln.info|45.33.88.134|United States
XLX736|xlx736.ddns.net|101.59.54.185|Italy
XLX737|83.212.170.243|83.212.170.243|Greece
XLX738|57.129.134.218|57.129.134.218|United Kingdom
XLX741|xrf741.xreflector-jp.org|203.137.78.41|Japan
XLX742|xlx-hc3.ddns.net|103.7.136.227|Ecuador
XLX743|xlx743.ddns.net|44.27.133.184|Ecuador
XLX744|xlx-hp3.dnsup.net|66.154.126.135|Panama
XLX745|xlx745.mydns.jp|131.129.105.238|Japan
XLX747|xlx747.de|78.47.190.213|Germany
XLX748|xlx748.dyndns.org|137.25.138.88|United States
XLX749|k2hzexlx.duckdns.org|104.238.162.147|United States
XLX750|xlx750.nz|203.86.206.49|New Zealand
XLX751|xlx751.drgau.au|45.76.123.136|Australia
XLX755|xlx.radioamateur.tk|89.234.155.6|Corsica
XLX757|xrf757.openquad.net|107.191.121.105|United States
XLX758|xlx758.0t0.jp|222.230.76.62|Japan
XLX760|xlx760.ddns.net|47.6.86.199|Perlas ng Silangan
XLX763|xlx.morten.dog.|104.42.53.140|United States
XLX765|ik1-342-31132.vs.sakura.ne.jp|153.126.212.136|Japan
XLX766|xlx.amrase.org.br|201.62.48.61|Brazil
XLX767|takshino.mydns.jp|133.232.90.95|Japan
XLX768|xlx.hamradio.pt|5.135.13.79|Portugal
XLX770|xrf770.mydns.jp|153.126.173.9|Tokushima JAPAN
XLX771|xlx771.duckdns.org|220.123.96.162|Korea
XLX772|xlx772.duckdns.org|146.56.185.110|Korea
XLX773|xlx773.iz0rin.it|89.36.210.213|Italy
XLX774|xlx774.ve2cyh.org|44.31.14.30|Canada
XLX775|xlx775.iz2qcp.it|51.38.27.230|Italy
XLX777|ealink.es|194.182.80.219|SPAIN
XLX778|xlx.hblink.kutno.pl|77.237.7.125|Poland
XLX781|xrf781.xreflector-jp.org|101.143.242.199|Japan
XLX787|46.41.1.96|46.41.1.96|Germany
XLX789|rf.ha.lc|45.33.119.142|United States
XLX790|xlx790.vdbg.nl|77.171.126.204|Netherlands
XLX794|xrf794.xreflector-jp.org|150.66.33.93|Japan
XLX797|xrf797.xreflector-jp.org|150.66.44.81|Japan
XLX798|92.247.20.2|92.247.20.2|Bulgaria
XLX799|xlxsof.ddns.net|84.238.136.188|Bulgaria
XLX800|xlx800.ddns.net|87.252.188.119|Bulgaria
XLX801|oe1phs.ddns.net|80.108.189.28|AUSTRIA - VIENNA OE1
XLX803|xlxcloverradio.digital|45.79.192.149|United States
XLX804|cloverxlxham.digital|45.79.195.149|United States
XLX805|xlx805.ddns.net|23.241.70.86|United States
XLX806|xlx806.ddns.net|188.63.22.20|D-STAR Austria Netz
XLX807|xrf807.owari.biz|116.91.197.3|Japan
XLX810|130.51.22.53|130.51.22.53|United States
XLX811|dstarjapan.pa7lim.nl|194.233.84.116|Japan
XLX812|xrf812.xreflector-jp.org|203.145.233.141|Japan
XLX814|xlx814.kr3l.org|44.199.151.113|United States
XLX815|xlx815.we0fun.com|66.241.100.145|United States
XLX816|xlx816.w4fe.com|35.199.38.36|USA - Levy Co, FL
XLX817|xlx817.w4fe.com|35.245.186.199|USA - Citrus Co, FL
XLX818|xlx818.hamnew.com|188.166.226.76|Thailand
XLX819|xlx.va2dfk.com|69.51.231.221|Canada
XLX820|xlx820.com|172.105.180.77|Australia
XLX822|xlx821.dstarthailand.com|141.98.17.18|Thailand
XLX823|kd2qqv.ddns.net|24.104.209.133|United States
XLX824|vk4rjwm17.com|194.195.126.139|Australia
XLX825|xlx.g6phf.co.uk|82.68.53.241|GB
XLX826|8.163.29.23|8.163.29.23|China
XLX827|xlx.kd5dfb.net|207.148.3.18|United States
XLX828|xlx.wm4wm.com|107.173.148.216|United States
XLX829|xlx829.spartanpcsecurity.com|172.233.189.243|United States
XLX830|lonestarlinksystem.com|162.255.119.164|United States
XLX831|xlx831.ddns.net|50.242.87.165|Santa Cruz, CA, USA
XLX833|xlx833.mydns.jp|203.136.242.199|Japan
XLX834|xlx834.mydns.jp|122.132.40.184|Japan
XLX835|wmrasystem.com|149.248.4.184|United States
XLX836|xlx.n7mky.com|45.56.69.219|United States
XLX838|185.166.212.132|185.166.212.132|Canary Islands
XLX839|xlx839.dyndns.org|15.223.114.236|United States
XLX840|xlx.gb3oa.org.uk|82.22.20.109|GB
XLX841|dvref.duckdns.org|158.180.80.27|Korea
XLX844|dv.afu.rwth-aachen.de|137.226.79.122|Germany
XLX845|xlx845.pota.review|71.174.60.28|United States
XLX847|xlx847.kk7mnz.com|98.171.104.209|United States
XLX850|xlx850.bm262.de|116.203.56.12|Germany
XLX858|xlx-host.top|172.236.254.232|United States
XLX860|24.134.86.93|24.134.86.93|Germany
XLX861|noradio86.ddns.net|86.254.3.249|FR
XLX862|it9bfb.ns0.it|195.231.118.80|Italy
XLX867|70.8.147.24|70.8.147.24|United States
XLX870|xlx870.nl|5.254.124.136|Netherlands
XLX876|xlxd.bh1ofp.com|172.67.168.245|China
XLX878|xrf878.xreflector-jp.org|203.137.123.113|Japan
XLX880|dashboard.on6uhf.com|81.83.4.238|Belgium
XLX883|153.127.25.123|153.127.25.123|Tokushima Japan
XLX885|xlx885.freeddns.it|188.217.45.105|Italy
XLX886|xlx886.metropit.net|118.163.103.178|Taiwan
XLX888|147.30.249.47|147.30.249.47|Kazakhstan
XLX892|urf892.cidcomm.com|209.251.60.132|United States
XLX893|893.pgw.jp|153.233.248.132|Japan
XLX895|xlx895.laukas.lt|69.123.143.14|United States
XLX897|xlx897.space|109.72.66.194|RF
XLX898|xlx.on7hh.be|213.186.33.5|Belgium
XLX900|xlx.kamenitza.org|212.72.212.173|Bulgaria
XLX901|urcat-xlx2.ddns.net|212.21.254.152|CATALUNYA
XLX902|reflector.miodek.me|93.104.128.3|Germany
XLX904|xrf904.xreflector-jp.org|150.66.5.57|Japan
XLX905|xlx905.oevsv.at|194.208.142.209|Austria
XLX909|xlx909.freeddns.org|44.32.128.17|Thailand
XLX910|xlx910.mywire.org|138.128.241.3|United States
XLX911|xlx911.patrweb.com|128.199.239.91|Thailand
XLX912|80.211.1.143|80.211.1.143|SPAIN
XLX913|xlx913.lmarc.net|68.169.168.32|United States
XLX914|47.156.44.132|47.156.44.132|World Wide
XLX916|myxlxw9gae.duckdns.org|173.28.155.67|United States
XLX917|xlx917.ddns.net|68.171.189.152|United States
XLX918|xlx918.180152.xyz|44.32.128.14|Thailand
XLX919|xlx919.freeddns.org|128.199.235.93|Thailand
XLX920|xlx.bruenderman.org|18.217.73.9|United States
XLX921|urf001.cumbriacq.com|89.240.4.99|CUMBRIA UK
XLX922|www.mb6er.com|81.150.10.62|United Kingdom
XLX923|urf923.lmarc.net|96.30.205.138|United States
XLX925|xlx925.hopto.org|185.26.243.94|GB
XLX927|k2as-ref.xyz|69.164.209.180|United States
XLX928|xlx928.ni2c.us|66.187.76.75|United States
XLX929|xlx929.vu2jjj.in|47.247.90.66|India
XLX930|89.46.70.60|89.46.70.60|Italy
XLX931|172.236.106.40|172.236.106.40|United States
XLX932|79.58.178.135|79.58.178.135|Italy
XLX933|xlx933.hamdigital.fr|51.254.33.194|France
XLX934|xlx934.arifvg.it|44.31.102.58|Italy
XLX935|xlx.n6lka.com|149.28.86.139|United States
XLX936|ysf.iu1olu.it|89.36.210.170|ITALY
XLX937|xlx.rc3c.ru|81.25.49.85|Russia
XLX938|g3brg.freeddns.org|95.146.183.211|United Kingdom
XLX939|relay.zaledia.com|185.44.82.42|Switzerland
XLX940|xlx940.vk2ym.com.au|101.167.170.95|Australia
XLX942|xlx942.ntsy.me|18.170.163.13|United Kingdom
XLX943|reflector.va3pdg.ca|15.235.72.7|Canada
XLX944|xrf944.xreflector-jp.org|202.218.34.210|Japan
XLX945|xlx945.freeddns.org|72.230.174.143|United States
XLX947|w8lrk-xlx947.ddnsfree.com|155.138.161.9|United States
XLX948|dashboard.icqpodcast.com|46.101.36.246|United Kingdom
XLX949|xlx949.isa-geek.com|149.248.3.1|United States
XLX950|xlx950.epf.lu|158.64.26.134|Luxembourg
XLX951|qnet.k4yrn.com|18.188.166.109|United States
XLX953|142.167.31.8|142.167.31.8|Canada
XLX956|xlx.dr4w.de|116.203.47.185|Germany
XLX957|87.106.196.53|87.106.196.53|Italy
XLX959|xrf959.xreflector-jp.org|203.137.98.121|Japan
XLX960|xlxlist.dyndns.org|104.153.109.233|Murphys, Ca. USA
XLX963|www.w5yiu.com|108.61.205.139|United States
XLX965|xlx965.hblink.it|44.31.102.220|Italy
XLX968|xlx.jlnet.net|69.169.99.254|United States
XLX969|urf.k0cks.com|72.133.49.122|United States
XLX975|w8lrk-xlx975.duckdns.org|207.174.245.170|United States
XLX976|xlx976.f8kgk.fr|80.12.83.150|France
XLX977|xlx.nwrg.org.uk|217.40.29.234|GB
XLX978|xlx978.dyndns.org|3.96.107.200|United States
XLX979|n5rwk.duckdns.org|74.118.151.43|United States
XLX980|hamradionyc.com|68.183.63.188|United States
XLX981|curiously-upward-pegasus.ngrok-free.app|184.72.44.51|United States
XLX982|w8lrk.dnsalias.org|24.128.192.232|United States
XLX983|XLX983.K8JTK.org|45.76.228.241|United States
XLX984|xlx984.hamradio.services|44.20.29.131|Denver, CO, USA
XLX985|xlx985.pa7ey.nl|213.10.4.86|Netherlands
XLX986|xlx986.thueringen.link|202.61.251.72|Germany
XLX987|xlx987.asuscomm.com|66.218.38.162|California USA
XLX988|xrf988.xreflector-jp.org|211.14.169.43|Japan
XLX989|xlx989.duckdns.org|66.118.221.14|United States
XLX990|xlx990.sapotech.com|116.80.84.230|Japan
XLX991|217.77.14.42|217.77.14.42|United Kingdom
XLX992|xlx992.2x2online.net|116.203.122.135|SPAIN
XLX993|fredarc-xlx.duckdns.org|69.251.56.54|United States
XLX994|urf994.ddns.net|45.32.181.77|United Kingdom
XLX997|xlx997.iw2gob.it|5.249.145.251|Italy
XLX998|82.165.6.239|82.165.6.239|United Kingdom
XLX999|94.177.204.159|94.177.204.159|Italy
XLXA51|xlx.hamonsite.com|159.65.190.18|USA - North MS
XLXA57|xrfa57.ddns.net|34.199.8.144|United States
XLXABL|xlxabl.duckdns.org|128.140.34.135|Germany
XLXACP|xlxacp.zukamore.co.za|102.67.58.154|South Africa
XLXARG|xlxarg.xlxreflector.org|47.206.136.224|USA - Florida
XLXAVM|xlx.km7beo.us|50.46.10.200|US - Washington
XLXBAS|xlxbas.dyndns.org|79.18.115.15|Italy
XLXBAT|82.85.236.36|82.85.236.36|ITALY
XLXBFN|xlxbfn.whitehat-security.org|204.111.254.236|United State
XLXBMW|xlxbmw.aga.waw.pl|185.193.112.137|Poland
XLXBOR|xlxbor.ddns.net|141.148.226.179|Netherlands
XLXBRA|xlxbra.net|177.131.119.153|Brazil
XLXBSL|xlxbsl.radioamateur.ca|149.56.130.169|Canada
XLXCAN|198.98.55.19|198.98.55.19|Canada
XLXCEL|urfcel-dashboard.funknetz-celle.de|217.160.0.17|Germany
XLXCHA|fzxq.x3322.net|27.156.107.47|CHINA
XLXCKG|tg46023.cn|8.154.40.3|China
XLXCMC|iz5cmc.hopto.org|188.217.43.247|Italy
XLXCNP|xlx.arsacnp.eu|51.91.58.99|SPAIN
XLXCOD|xlxcod.com|109.237.26.51|United Kingdom
XLXCOW|xlxcow.nh6fu.com|44.62.14.126|United States
XLXCZE|jedi.ok2it.com|46.28.109.166|Czech_Republic
XLXCZS|128.0.182.6|128.0.182.6|Czechia
XLXD51|xlxd51.ddns.net|192.227.177.138|Greece
XLXDAM|digital-america.org|104.21.62.102|United States
XLXDEU|ysf-deutschland.de|85.215.138.68|Germany
XLXDF8|xlx.df8mr.net|185.84.4.133|Germany
XLXDIG|urf.w3lby.com|149.56.147.144|United States
XLXDLN|xlx.radiorabbit.ca|158.69.201.52|Canada
XLXE2H|e2hub.vra.or.th|209.15.117.65|THAILAND
XLXE51|192.227.177.16|192.227.177.16|Greece
XLXEAR|gb7wy.co.uk|213.171.208.97|United Kingdom
XLXEMB|xlx.bugsbgone.au|159.196.65.11|Australia
XLXEMI|ik4nzd.ns0.it|82.55.21.231|ITALY
XLXEMO|217.160.38.80|217.160.38.80|ITALY
XLXEND|xlxend.mywire.org|78.43.3.127|Germany
XLXEUS|eus.ham-radio-op.net|88.9.254.159|Basque Country
XLXFOX|xlxfox.foxhole.radio|20.236.251.104|United States
XLXFRA|xlxfra.ddns.net|82.165.136.30|Italy
XLXGBP|xlxgbp.n9muf.org|75.145.166.70|United States
XLXGOE|xlxgoe.ddnss.org|87.106.26.8|Germany
XLXGR1|hamsat.eu|172.67.175.240|Greece
XLXGUN|xrfgun.org|128.22.137.179|Japan
XLXHAM|xlxham.ircddb.it|91.121.90.186|Italy
XLXHDH|xlxhdh.ddns.net|34.199.8.144|Netherlands
XLXHKG|xlxhkg.hkham.net|58.153.251.8|Hong Kong, China
XLXHRT|xlxhrt.camdvr.org|212.132.119.189|Germany
XLXHUB|onurbespinar.tplinkdns.com|78.175.21.171|Türkiye
XLXIDN|xlx.ip-trunk.my.id|101.255.4.222|Indonesia
XLXIGS|xlxigs.fnoy.info|104.21.82.181|Japan
XLXIHH|ik6ihh.ddns.net|109.239.250.3|Italy
XLXILS|xlxils.w9ils.org|66.42.118.123|United States
XLXIS0|xlxis0.is0.org|51.254.206.201|Sardinia Island
XLXIT1|xlxit1.ircddb.it|141.94.26.117|ITALY
XLXITA|xlx-ita.dyndns.org|46.226.178.85|ITALY
XLXITM|urfitm.dyndns.org|46.226.178.86|ITALY
XLXJAX|jax-beach.hamfm.com|3.82.79.112|United States
XLXJDV|xlxjdv.freedmr.it|44.31.102.155|Italy
XLXJET|5.161.215.224|5.161.215.224|United States
XLXJSS|innet.tplinkdns.com|70.16.65.11|United States
XLXKHW|xlxkhw.fnoy.info|104.21.82.181|Japan
XLXKSJ|urfdash.k0eg.radio|104.21.81.164|United States
XLXLE1|80.211.135.179|80.211.135.179|Italy
XLXLEF|xlxlef.gb7hh.co.uk|77.68.25.66|United Kingdom
XLXLWT|xlx.kb7dan.com|172.232.11.89|United States
XLXMDM|140.83.39.35|140.83.39.35|Japan
XLXMIL|xlxmil.dk9bt.net|92.5.65.131|Germany
XLXMLB|xlxmlb.n0oj.net|144.129.188.190|United States
XLXMMG|xlxmmg.nemmg.club|137.103.112.175|United States
XLXMYR|xlx.hamsup.my|103.7.9.22|Malaysia
XLXNFL|xlxnfl.wt0f.com|38.59.40.10|United States
XLXNLD|dstarnld.pa7lim.nl|90.145.156.214|Netherlands
XLXNPP|49.232.24.178|49.232.24.178|China
XLXNRW|do1di.nrw|168.119.26.12|NRW / Germany
XLXOWG|xlx.m7owg.uk|84.43.120.34|United Kingdom
XLXPAW|urfpaw.11cats.org|216.128.141.250|United States
XLXPNW|xlxpnw.duckdns.org|50.47.179.32|United States
XLXPNY|dstarbrasil.com.br|82.152.174.236|Brazil
XLXPOL|xlx.minilink.pl|185.139.125.173|Poland
XLXPRC|120.197.207.2|120.197.207.2|China
XLXPTA|xlxpta.zs6tvb.xyz|206.189.17.7|South Africa
XLXQRZ|qrz.cqnet.org|46.59.68.211|HELLAS Zone Net!
XLXQZX|k9qzx.duckdns.org|172.236.99.56|United States
XLXRC1|xlxrc1.radiocult.su|91.247.248.67|Russia
XLXRHR|xlx.remotehamradio.com|54.221.237.54|USA-NY
XLXRHX|xlxrhx.sq9.online|87.205.19.162|Poland
XLXRUS|44.32.144.35|44.32.144.35|RUSSIA
XLXSAT|xlx3.k5wh.net|149.28.241.139|United States
XLXSCP|xlxscp.iv3scp.it|44.31.102.148|Italy
XLXSIN|xlx.w9winxlx.us|34.198.182.201|United States
XLXSOM|45.33.73.221|45.33.73.221|United States
XLXSP5|xlxsp5.ddns.mobi|79.162.210.62|Poland
XLXSPB|xlxspb.qth.spb.ru|195.209.49.123|Russia
XLXSPC|xlxspc.spacecoasttelecom.com|20.169.238.174|United States
XLXSVD|xlxsvd.duckdns.org|87.106.53.226|Italy
XLXTEN|xlxten.ddns.net|15.204.205.35|United States
XLXTEX|xlx.n5hme.net|104.237.135.47|United States
XLXTNH|tnhams.net|104.21.46.138|United States
XLXTYL|xlxtyl.itsmith.com|66.179.209.225|United States
XLXTYO|xrftyo.mydns.jp|43.233.9.107|Japan
XLXUDN|xrfudn.mydns.jp|133.123.221.104|Japan
XLXUFB|xlx.ufbnewengland.com|97.107.140.110|United States
XLXUFO|xlx.ufo.amwan.net|34.223.210.43|United States
XLXURU|uruguaynet1.2mydns.net|198.245.55.26|MONTEVIDEO URUGUAY
XLXUS1|xlxus1.w4fe.com|34.75.201.117|USA - EST
XLXUS2|xlxus2.w4fe.com|34.68.104.251|USA - CST
XLXUS3|xlxus3.w4fe.com|34.125.157.223|USA - MST
XLXUS4|xlxus4.w4fe.com|34.94.168.67|USA - PST
XLXUS5|xlxus5.w4fe.com|35.235.109.69|USA - Backup
XLXUSA|xlxusa.w4fe.com|35.232.145.123|United States
XLXUTC|xlxutc.kr0ot.com|67.199.170.136|United States
XLXUTR|xlx.pi4utr.nl|5.254.117.43|Netherlands
XLXV69|XLXV69.DDNS.NET|73.127.69.215|United States
XLXVE1|xlxve1.candx.ca|44.32.224.141|CANADA-MARITIMES
XLXVE2|xlxve2.candx.ca|44.32.224.142|CANADA-QC
XLXVE3|xlxve3.candx.ca|44.32.225.44|CANADA-ONT
XLXVE4|xlxve4.candx.ca|44.32.224.144|CANADA-MB
XLXVE5|xlxve5.candx.ca|44.32.224.145|CANADA-SASK
XLXVE6|xlxve6.candx.ca|44.32.224.146|CANADA-AB
XLXVE7|xlxve7.candx.ca|44.32.224.147|CANADA-BC
XLXVPS|44.31.15.201|44.31.15.201|Quebec - Canada
XLXWA1|xlxwa1.kk7okt.net|172.234.231.226|United States
XLXWDX|xlxwdx.worldwidedx.com|165.232.157.210|United States
XLXWRN|70.73.135.36|70.73.135.36|Canada
XLXWSL|213.219.147.227|213.219.147.227|BELGIUM
XLXXME|deez.vnutz.com|159.89.176.136|United States
XLXXXX|world.cq-uk.co.uk|81.150.10.63|United Kingdom
XLXYAI|xlxyai.ja3yai.club|203.138.145.124|JAPAN
XLXYEG|219.117.204.205|219.117.204.205|JAPAN
XLXYEK|125.199.48.156|125.199.48.156|Japan
XLXYKO|xrfyko.mydns.jp|59.129.208.225|Japan
XLXYLV|xlxylv.ta2kw.keenetic.pro|85.103.82.115|TÜRKİYE
XLXYO2|xlxyo2.yo2lyn.link|84.232.226.95|Romania
XLXZVU|176.128.229.6|176.128.229.6|FR
"""

// swiftlint:enable file_length
