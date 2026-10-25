class AppCountry {
  final String code;
  final String name;
  final String flag;

  const AppCountry({
    required this.code,
    required this.name,
    required this.flag,
  });

  static AppCountry fromCode(String code) {
    return kPopularCountries.firstWhere(
      (c) => c.code.toUpperCase() == code.toUpperCase(),
      orElse: () => kPopularCountries.first,
    );
  }

  static AppCountry fromName(String name) {
    return kPopularCountries.firstWhere(
      (c) => c.name.toLowerCase() == name.toLowerCase() || c.name.toLowerCase().contains(name.toLowerCase()),
      orElse: () => kPopularCountries.first,
    );
  }
}

const List<AppCountry> kPopularCountries = [
  AppCountry(code: 'ALL', name: 'Global (Worldwide)', flag: '🌍'),
  AppCountry(code: 'US', name: 'United States', flag: '🇺🇸'),
  AppCountry(code: 'GB', name: 'United Kingdom', flag: '🇬🇧'),
  AppCountry(code: 'CA', name: 'Canada', flag: '🇨🇦'),
  AppCountry(code: 'AU', name: 'Australia', flag: '🇦🇺'),
  AppCountry(code: 'PK', name: 'Pakistan', flag: '🇵🇰'),
  AppCountry(code: 'IN', name: 'India', flag: '🇮🇳'),
  AppCountry(code: 'DE', name: 'Germany', flag: '🇩🇪'),
  AppCountry(code: 'FR', name: 'France', flag: '🇫🇷'),
  AppCountry(code: 'ES', name: 'Spain', flag: '🇪🇸'),
  AppCountry(code: 'IT', name: 'Italy', flag: '🇮🇹'),
  AppCountry(code: 'TR', name: 'Turkey', flag: '🇹🇷'),
  AppCountry(code: 'AE', name: 'United Arab Emirates', flag: '🇦🇪'),
  AppCountry(code: 'SA', name: 'Saudi Arabia', flag: '🇸🇦'),
  AppCountry(code: 'BR', name: 'Brazil', flag: '🇧🇷'),
  AppCountry(code: 'MX', name: 'Mexico', flag: '🇲🇽'),
  AppCountry(code: 'JP', name: 'Japan', flag: '🇯🇵'),
  AppCountry(code: 'KR', name: 'South Korea', flag: '🇰🇷'),
  AppCountry(code: 'PH', name: 'Philippines', flag: '🇵🇭'),
  AppCountry(code: 'ID', name: 'Indonesia', flag: '🇮🇩'),
  AppCountry(code: 'NL', name: 'Netherlands', flag: '🇳🇱'),
  AppCountry(code: 'SE', name: 'Sweden', flag: '🇸🇪'),
  AppCountry(code: 'NO', name: 'Norway', flag: '🇳🇴'),
  AppCountry(code: 'CH', name: 'Switzerland', flag: '🇨🇭'),
  AppCountry(code: 'NZ', name: 'New Zealand', flag: '🇳🇿'),
  AppCountry(code: 'ZA', name: 'South Africa', flag: '🇿🇦'),
  AppCountry(code: 'EG', name: 'Egypt', flag: '🇪🇬'),
  AppCountry(code: 'BD', name: 'Bangladesh', flag: '🇧🇩'),
];
