Pod::Spec.new do |s|
  s.name             = 'ra7al_muxer'
  s.version          = '1.0.0'
  s.summary          = 'Joins video and audio tracks without re-encoding.'
  s.homepage         = 'https://github.com/maimoni303/ra7alsaver'
  s.license          = { :type => 'GPL-3.0' }
  s.author           = { 'RA7AL' => 'maimoni3003@gmail.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.frameworks       = 'AVFoundation'
  s.platform         = :ios, '13.0'
  s.swift_version    = '5.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
