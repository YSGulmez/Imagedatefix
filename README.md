# Foto Tarih Düzenleyici (Image Date Fixer)

Dosya adlarındaki tarihleri okuyup, bu tarihleri fotoğraf ve videoların metadata (EXIF/QuickTime) alanlarına gömen, dosyaları organize eden ve kopyaları ayıklayan kapsamlı bir araçtır.

## 🚀 Özellikler

### Tarih Çözümleme
- **Çoklu Format Desteği:** `20240127`, `2024-01-27`, `2024-01-27 14:30:25` ve milisaniye zaman damgalarını otomatik tanır.
- **Unix Zaman Damgası:** Dosya adındaki 9-13 haneli Unix zaman damgalarını tarihe çevirir.
- **Varsayılan Tarih:** Tarihi bulunamayan dosyalar için kullanıcı tarafından belirlenen bir varsayılan tarih atanabilir.

### Metadata Yazma
- **Fotoğraflar:** JPEG, PNG, HEIC, WEBP formatlarında EXIF tarihleri güncellenir.
- **Videolar (Windows):** MP4, MOV, M4V, 3GP formatlarında QuickTime ve Keys metadata alanları güncellenir.
- **Dosya Sistemi:** Yazma işlemi sonrası dosyanın "Son Değiştirilme Tarihi" de güncellenir.

### Organizasyon ve Temizlik
- **Yıllara Göre Ayırma:** Dosyalar tarihlerine göre `2024`, `2025`, `2026` gibi klasörlere otomatik taşınır.
- **Ekran Görüntüsü Ayrıştırma:** "Screenshot", "ScreenCap" vb. içeren dosyalar ayrı bir klasöre taşınır.
- **Snapchat Desteği:** Snapchat dosyaları özel olarak algılanır ve ayrı klasörlenir.
- **Alt Klasör Taraması:** Tüm alt dizinlerdeki medyalar taranabilir.
- **Kopya Temizleme (Karantina):** SHA-256 hash ile birebir kopyalar bulunur ve `_Karantina` klasörüne taşınır. Arayüz üzerinden geri alınabilir veya kalıcı olarak silinebilir.

## 💻 Kurulum ve Kullanım

### Windows
1. **ExifTool Gereksinimi:** Uygulamanın çalışması için [ExifTool](https://exiftool.org/) gereklidir.
2. **Çalıştırma:** `flutter run -d windows` komutuyla veya derlenmiş .exe üzerinden başlatın.
3. **Ayarlar:** Uygulama içinden ExifTool'un bilgisayarınızdaki yolunu belirtin.

### Android
1. APK dosyasını cihazınıza yükleyin.
2. Klasör seçimi yaparak tarihleri güncelleyin.
3. `_Karantina` klasörü üzerinden kopya yönetimi yapın.

## 📊 Raporlama
İşlem sonunda detaylı bir sonuç ekranı sunulur:
- Taranan toplam medya sayısı.
- Başarıyla yazılan ve tarih bulunamayan dosyaların sayısı.
- Problemli dosyaların listesi ve küçük önizlemeleri.
- Başarı yüzdesi ve canlı ilerleme çubuğu.

## ⚠️ Önemli Uyarılar
- **Yedekleme:** Dosyalar yerinde düzenlenir ve taşınır. İşlem öncesi verilerinizin yedeğini almanız önerilir.
- **Karantina:** Dosyalar kalıcı olarak silinmeden önce mutlaka `_Karantina` klasöründe kontrol edilmelidir.
