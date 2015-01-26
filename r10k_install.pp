class { 'r10k':
  version           => '1.2.1',
  sources           => {
    'puppet' => {
      'remote'  => 'https://github.com/CloudOpting/puppet-environment.git',
      'basedir' => "${::settings::confdir}/environments",
      'prefix'  => false,
    },
    'hiera' => {
      'remote'  => 'https://github.com/CloudOpting/hiera-environment.git',
      'basedir' => "${::settings::confdir}/hiera",
      'prefix'  => false,
    }
  },
  purgedirs         => ["${::settings::confdir}/environments"],
  manage_modulepath => true,
  modulepath        => "${::settings::confdir}/environments/\$environment/modules:/opt/puppet/share/puppet/modules",
  install_options   => '--debug', # to fix finding '' gem
}
