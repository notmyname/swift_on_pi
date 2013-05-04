Swift on Pi
===========

This annotated script sets up a limited deployment of OpenStack Swift
onto a Raspberry Pi. It sets up a one-replica, one-server environment
appropriate for external testing. It assumes there is a user called "pi"
and that user has sudo access (this is the default on a Raspberry Pi).

## To Run Functional Tests

    cd /path/to/swift/source/tree
    SWIFT_TEST_CONFIG_FILE=/path/to/swift_on_pi/swift_raspberry_pi_functional_tests.conf ./.functests
