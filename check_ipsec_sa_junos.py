#!/usr/bin/python
# $id mleucht (C) I/P/B/ GmbH  
#
# TODO: Implement SNMPv3 support

import subprocess
import sys

global snmpversion
global snmpcommunity
global snmphost
global ikegw
global snmpoid
global errors
errors = {"OK" : 0, "CRITICAL" : 2}

def shell_exec():
        snmphost=sys.argv[1]
        snmpversion=sys.argv[2]
        snmpcommunity=sys.argv[3]
        ikegw=sys.argv[4]
        snmpoid=".1.3.6.1.4.1.2636.3.52.1.2.3.1.14.1.4." + ikegw
        try:
                p = subprocess.Popen(["snmpbulkwalk", "-v" + snmpversion, "-c" + snmpcommunity, snmphost, snmpoid, "-Ovq"], stdout=subprocess.PIPE)
                output, err = p.communicate()
                return output,err
        except subprocess.CalledProcessError:
                print "Something bad happened"
                sys.exit(errors['CRITICAL'])
def main():
        tunneldesc=sys.argv[5]
        try:
                output = shell_exec()
                retval=int(output[0])

                if retval == 1:
                        print "OK SA for IPSec Tunnel " + tunneldesc + " is ready for active use"
                        sys.exit(errors['OK'])
                else:
                        print "CRITICAL SA for IPSec Tunnel " + tunneldesc + " is not active"
                        sys.exit(errors['CRITICAL'])

        except ValueError:
                print "An error occured, perhaps IKE Gateway for " + tunneldesc + " is not configured on that device"
                sys.exit(errors['CRITICAL'])


def help():
        print "Usage: ./" + sys.argv[0] + " [SNMPversion] [SNMPcommunity] [SNMPHost (IP or FQDN)] [IP of IKE Gateway] [descriptive name of IPSec Tunnel]"

#stub to launch main
if __name__ == '__main__':
        if len(sys.argv) < 6:
                help()
                sys.exit(errors['CRITICAL'])
        else:
                main()

# vim: tabstop=8 expandtab shiftwidth=4 softtabstop=4
