# Just some hacking at PuppetConf, a plan to do a quick CPU benchmark on a new GCE instance
plan puppetconf2017::cpubench($credential, $project) {

  # Pure laziness...probably better to pick the minimum scopes
  $fn_auth = gauth_credential_serviceaccount_for_function(
    $credential, ['https://www.googleapis.com/auth/cloud-platform']
  )

  # Starts me a new randomly named instances and returns that name to be stored
  # in the $instance variable
  $instance = run_task(gcompute::instance, 'localhost', {
    credential         => $credential,
    project            => $project,
    zone               => 'us-west1-c',
    image_family       => 'ubuntu-1604-lts:ubuntu-os-cloud',
    allocate_static_ip => true,
  })['localhost']['name']

  # We didn't create a task for creating a new bucket...so this is effectively
  # an inline "puppet apply" based "task" for creating one.  Bolt kinda gives
  # you an API for making random hacks maintainable.
  $manifest = inline_epp("\"gauth_credential { 'mycred':
      path     => '$credential',
      provider => serviceaccount,
      scopes   => ['https://www.googleapis.com/auth/cloud-platform'],
    }
    gstorage_bucket { $instance:
      ensure     => present,
      project    => $project,
      credential => 'mycred',
    }\""
  )

  # Runs our manifest from above
  run_command("/opt/puppetlabs/bin/puppet apply -e $manifest", 'localhost')

  # Grabs the IP address from GCE using the returned name of our new instance so
  # we can use it to login to it and do more work
  $instance_ip = gcompute_address_ip($instance, 'us-west1', $project, $fn_auth)

  # I couldn't a working task for installing Puppet, when I do this ugliness
  # will go away
  run_command('wget -O /tmp/puppet.deb http://apt.puppetlabs.com/puppet5-release-xenial.deb && dpkg -i /tmp/puppet.deb && rm /tmp/puppet.deb', "ssh://root@${instance_ip}")
  run_command('apt update && apt install -y puppet-agent', "ssh://root@${instance_ip}")
  run_command('/opt/puppetlabs/puppet/bin/gem install googleauth google-api-client', "ssh://root@${instance_ip}")


  run_task(package, "ssh://root@${instance_ip}", {
    action  => install,
    name    => 'sysbench'
  })

  run_command("sysbench --test=cpu --cpu-max-prime=20000 run >/tmp/${instance}-results.txt", $instance_ip)

  file_upload($credential, '/tmp/credential.json', $instance_ip)

  run_command('/opt/puppetlabs/bin/puppet module install google/cloud', $instance_ip)

  run_task(gstorage::upload, $instance_ip, {
    name       => "${instance}-results.txt",
    source     => "/tmp/${instance}-results.txt",
    bucket     => $instance,
    project    => $project,
    credential => '/tmp/credential.json',
  })
}
