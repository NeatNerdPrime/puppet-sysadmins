# File::      <tt>sysadmin.pp</tt>
# Author::    Sebastien Varrette (Sebastien.Varrette@uni.lu)
# Copyright:: Copyright (c) 2011 Sebastien Varrette
# License::   GPLv3
# ------------------------------------------------------------------------------
# = Class: sysadmin
#
# Configure a system administrator account for (potentially) several  users
#
# == Parameters: (cf sysadmin-params.pp)
#
# $login:: *Default*: 'localuser'. The actual login used for the account
#
# $email:: *Default*: ''. Redirect all mails sent to the sysadmin account to this email address
#
# $groups:: *Default*: []. Additonnal groups the above user is member of
#
# $ensure:: *Default*: 'present'. The Puppet ensure attribute (can be either 'present' or 'absent') - absent will ensure the user is removed
#
# == Actions:
#
# Install and configure a local sysadmin
#
# == Requires:
#
# ssh::server
#
# == Sample Usage:
#
#     import sysadmin
#
# You can then specialize the various aspects of the configuration,
# for instance:
#
#         class { 'sysadmin':
#             login   => 'localadmin',
#         }
#
# This will:
#
# * create a local account 'localadmin'
# * configure its homedir
#
# To associate to this local account a real user, just call (see sysadmin::user definition)
#
#        sysadmin::user{ 'svarrette':
#              firstname => 'Sebastien',
#              lastname  => 'Varrette',
#              email     => 'Sebastien.Varrette@uni.lu',
#              sshkeys   => {
#                  comment  => 'svarrette@falkor.uni.lux',
#                  type     => 'ssh-dss',
#                  key      => 'AAAAB3NzaC1kc3[...]Akdld'
#              }
#
#  This will complete the file ~/.sysadminrc (used to identified who logged) and add its SSH key
#  to the ~localadmin/.ssh/authorized_keys
#  The sshkeys parameter is optional, you can add an SSH to a real user at any moment by
#  invoking (see sysadmin::user::sshkey definition):
#
#        sysadmin::user::sshkey{'svarrette@anothermachine':
#              username => 'svarrette',
#              type     => 'ssh-rsa',
#              key      => 'AAAAB3NzaC1yc2E[...]TOZZajX/sUGpQ=='
#        }
#
# == Warnings
#
# /!\ Always respect the style guide available
# here[http://docs.puppetlabs.com/guides/style_guide]
#
#
# [Remember: No empty lines between comments and class definition]
#
class sysadmin(
    $login   = $sysadmin::params::login,
    $email   = $sysadmin::params::email,
    $ensure  = $sysadmin::params::ensure
)
inherits sysadmin::params
{
    info ("Configuring sysadmin (login = ${login}, ensure = ${ensure})")

    if ! ($ensure in [ 'present', 'absent' ]) {
        fail("sysadmin 'ensure' parameter must be either absent or present")
    }

    case $::operatingsystem {
        debian, ubuntu:         { include sysadmin::debian }
        redhat, fedora, centos: { include sysadmin::redhat }
        default: {
            fail("Module $module_name is not supported on $operatingsystem")
        }
    }
}

# ------------------------------------------------------------------------------
# = Class: sysadmin::common
#
# Base class to be inherited by the other sysadmin classes
#
# Note: respect the Naming standard provided here[http://projects.puppetlabs.com/projects/puppet/wiki/Module_Standards]
class sysadmin::common {

    # Load the variables used in this module. Check the ssh-server-params.pp file
    require sysadmin::params

    include concat::setup

    ############# VARIABLES ###########
    # sysadmin user homedir
    $homedir = "${sysadmin::params::homebasedir}/${sysadmin::login}"
    # main configuration file for sysadmin
    $sysadminrc = "${homedir}/${sysadmin::params::configfilename}"

    ####################################
    # Create the user
    user { "${sysadmin::login}":
        ensure     => "${sysadmin::ensure}",
        allowdupe  => false,
        comment    => 'Local System Administrator',
        home       => "${homedir}",
        managehome => true,
        groups     => $sysadmin::groups,
        shell      => '/bin/bash',
        require    => Class['augeas'],
    }


    if $sysadmin::ensure == 'present' {
        file { "${homedir}":
            ensure    => 'directory',
            owner     => "${sysadmin::login}",
            group     => "${sysadmin::login}",
            mode      => "${sysadmin::params::dirmode}",
            require   => User["${sysadmin::login}"]
        }

        # Initialize bash
        include bash

        bash::setup { "${homedir}":
            ensure  => "${sysadmin::ensure}",
            user    => "${sysadmin::login}",
            group   => "${sysadmin::login}",
            require => File["${homedir}"]
        }

        file { "${homedir}/.profile":
            ensure  => "${sysadmin::ensure}",
            owner   => "${sysadmin::login}",
            group   => "${sysadmin::login}",
            mode    => "${sysadmin::params::filemode}",
            content => template("sysadmin/bash_profile.erb"),
            require   => User["${sysadmin::login}"]
        }

        # Initialize ssh directory
        file { "${homedir}/.ssh":
            ensure    => 'directory',
            recurse   => true,
            force     => true,
            owner     => "${sysadmin::login}",
            group     => "${sysadmin::login}",
            mode      => "${sysadmin::params::dirmode}",
            require   => User["${sysadmin::login}"]
        }
        file { "${homedir}/.ssh/authorized_keys":
            ensure    => 'present',
            owner     => "${sysadmin::login}",
            group     => "${sysadmin::login}",
            mode      => "0600",
            require   => [
                          User["${sysadmin::login}"],
                          File["${homedir}/.ssh"]
                          ]
        }

        # prepare a bin/ directory
        file { "${homedir}/bin":
            ensure    => 'directory',
            owner     => "${sysadmin::login}",
            group     => "${sysadmin::login}",
            mode      => "${sysadmin::params::dirmode}",
            require   => User["${sysadmin::login}"]
        }

        # initialize the configuration file
        concat { "${sysadminrc}":
            owner   => "${sysadmin::login}",
            group   => "${sysadmin::login}",
            mode    => "${sysadmin::params::filemode}",
            require => User["${sysadmin::login}"]
        }
        concat::fragment { "sysadminrc_header":
            target  => "${sysadminrc}",
            source  => "puppet:///modules/sysadmin/sysadminrc_header",
            order   => 01,
        }

        concat::fragment { "sysadminrc_footer":
            target  => "${sysadminrc}",
            source  => "puppet:///modules/sysadmin/sysadminrc_footer",
            order   => 99,
        }

        # Update SSH server configuration
        require ssh::server

        ssh::server::conf::acceptenv { 'SYSADMIN_USER': }

        exec { "Lock the password of the ${sysadmin::login} account":
            path    => '/sbin:/usr/bin:/usr/sbin:/bin',
            command => "passwd --lock ${sysadmin::login}",
            unless  => "passwd -S ${sysadmin::login} | grep '^${sysadmin::login} L'",
            user    => 'root',
            require => User["${sysadmin::login}"]
        }

        # Add the sysadmin to the sudoers file
        sudo::directive { "${sysadmin::login}_in_sudoers":
            content => "${sysadmin::login}    ALL=(ALL)   NOPASSWD:ALL\n",
        }

        # Complete the /etc/aliases files for the '${sysadmin::login}' entry
        # i.e. add this mail to the array of mails
        if ($ensure == 'present') and ($email != '') {
            notice("adding ${email} to the mailist [ $sysadmin::params::maillist ]")
            $sysadmin::params::maillist += "${email}"
        }

    }
    else {

        # Unlock the root account
        exec { "Unlock the password of the ${sysadmin::login} account":
            path    => '/sbin:/usr/bin:/usr/sbin:/bin',
            command => "passwd --unlock ${sysadmin::login}",
            onlyif  => "passwd -S ${sysadmin::login} | grep '^${sysadmin::login} L'",
            user    => 'root'
        }

    }

    ### Add (or remove) the sysadmin mails to the /etc/aliases files (create a
    ### stage to be run at the end for this purpose
    stage { 'sysadmin_last':  require => Stage['main'] }
    #stage { 'sysadmin_first': before  => Stage['main'] }
    class { 'sysadmin::mail::aliases':
        stage => 'sysadmin_last'
    }

}

# ------------------------------------------------------------------------------
# = Class: sysadmin::debian
#
# Specialization class for Debian systems
class sysadmin::debian inherits sysadmin::common { }

# ------------------------------------------------------------------------------
# = Class: sysadmin::redhat
#
# Specialization class for Redhat systems
class sysadmin::redhat inherits sysadmin::common { }



# ------------------------------------------------------------------------------
# = Class: sysadmin::mail::aliases
#
# INTERNAL USAGE ONLY (inside the class 'sysadmin') - stages required to
# externalize the code in a separate class to work (see http://docs.puppetlabs.com/guides/language_guide.html#resource-collections)
#
# Set mail aliases for sysadmins. This class is meant to be run in a last stage
# by the class sysadmin once the array ${sysadmin::params::maillist} is fully
# populated by the successive calls to sysadmin::user.
#
# == Require
#
# * the sysadmin class should have been instanciated
# * the stage 'sysadmin_last' should have been defined
#
class sysadmin::mail::aliases {

    # Load the variables used in this module.
    require sysadmin::params
    # Load the common functions
    include common

    # Create an entry for ${sysadmin::login} in /etc/aliases
    notice("updating ${sysadmin::login} mail aliases (on '${sysadmin::params::maillist}')")
    mailalias { "${sysadmin::login}":
        ensure    => "${sysadmin::ensure}",
        recipient => $sysadmin::params::maillist,
    }
    #$required = Mailalias["${sysadmin::login}"]

    # Update the root entry by adapting the current list (from the custom fact -- see
    # modules/common/lib/facter/mail_aliases.rb)
    $current_root_maillist = split($::mail_aliases_root, ',')

    $tmp_root_maillist = array_include($current_root_maillist, "${sysadmin::login}") ? {
        false   => [ "${sysadmin::login}", $current_root_maillist ],
        default => $current_root_maillist
    }

    # TODO: removal DO NOT work. TO BE FIXED
    $real_root_maillist = $sysadmin::ensure ? {
        'present' => $tmp_root_maillist,
        # remove ${sysadmin::login} from root mail entries if ensure != present
        default   => array_del(flatten(uniq($tmp_root_maillist)), "${sysadmin::login}")
    }

    mailalias { "root":
        ensure    => "${sysadmin::ensure}",
        recipient => uniq(flatten($real_root_maillist)),
        require   => Mailalias["${sysadmin::login}"]
    }


    # If ${sysadmin::login} is associated to at least 1 valid email address,
    # install the additionnal packages that assume some valid email adress to
    # notify (ex: logwatch, logcheck)
    if $sysadmin::params::maillist {
        package { $sysadmin::params::utils_packages:
            ensure => "${sysadmin::ensure}",
        }
    }


}
