#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html
#
Pod::Spec.new do |s|
  s.name             = 'nfc_in_flutter'
  s.version          = '1.0.0'
  s.summary          = 'Flutter plugin for reading NFC tags'
  s.description      = 'Flutter plugin for reading NFC tags'
  s.homepage         = 'https://github.com/semlette/nfc_in_flutter'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Andi Robin Halgren Semler' => 'andirobinsemler@gmail.com' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.public_header_files = 'Classes/**/*.h'
  s.dependency 'Flutter'
  s.weak_frameworks = ['CoreNFC']

  s.ios.deployment_target = '8.0'
end

