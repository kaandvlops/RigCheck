# RigCheck Pro // Depo & Teknik Servis Donanım Teşhis & QA Otomasyonu

Bilgisayar montaj ve teknik servis operasyonlarında (özellikle hazır oyuncu sistemleri ve iade süreçlerinde) donanım doğrulama, XMP tespiti, disk sağlık analizi ve otomatik işletim sistemi dağıtımını standartlaştırmak için geliştirilmiş taşınabilir bir teknisyen aracıdır.

## 🚀 Özellikler

- **Donanım Denetimi (WMI / CIM):** CPU, GPU, Anakart seri numarası, RAM kapasitesi, slot dağılımı ve frekanslarını saniyeler içinde analiz eder.
- **XMP / DOCP Doğrulayıcı:** RAM frekanslarını kontrol ederek taban değerde (2133/2400 MHz) kalan sistemler için teknisyeni uyarır.
- **Depolama & SMART Taraması:** Fiziksel disklerin operasyonel durumunu ve SMART sağlık verilerini listeler.
- **Hızlı Stabilite Testi:** 20 saniyelik çok çekirdekli CPU stres testi ile montaj, termal macun ve kapanma arızalarını simüle eder.
- **Otomatik QA Sertifikası (HTML):** Test tamamlandığında anakart seri numarasıyla eşleşen, kutu üstüne veya servis dosyasına eklenebilecek standart kalite kontrol fişi üretir.
- **Ventoy & Unattended Entegrasyonu:** Diski olmayan kasalarda WinPE üzerinden başlatılabilir; `autounattend.xml` ile sıfır etkileşimli Windows 11 kurulumunu destekler.

## 📁 Proje Yapısı

- `Araclar/RigCheck.ps1`: WPF grafik arayüzlü ana donanım test motoru.
- `Araclar/Baslat.bat`: Tek tıkla yetki kısıtlamalarını aşarak aracı başlatan tetikleyici.
- `autounattend.xml`: Katılımsız Windows kurulum yanıt dosyası.
- `ventoy/ventoy.json`: Ventoy otomatik imaj ilişkilendirme yapılandırması.

## 🛠️ Kurulum ve Kullanım

1. Repodaki dosyaları Ventoy ile yapılandırılmış USB belleğe aktarın.
2. Windows altında veya WinPE ortamında `Araclar/Baslat.bat` dosyasını çalıştırın.
3. Donanımı tarayın, stabilite testini tamamlayın ve tek tıkla servis raporunu yazdırın.