package FusionInventory::Agent::Task::Inventory::Input::Win32::Printers;

use strict;
use warnings;

use English qw(-no_match_vars);

use FusionInventory::Agent::Tools::Win32;

my @status = (
    'Unknown', # 0 is not defined
    'Other',
    'Unknown',
    'Idle',
    'Printing',
    'Warming Up',
    'Stopped printing',
    'Offline',
);

my @errStatus = (
    'Unknown',
    'Other',
    'No Error',
    'Low Paper',
    'No Paper',
    'Low Toner',
    'No Toner',
    'Door Open',
    'Jammed',
    'Service Requested',
    'Output Bin Full',
    'Paper Problem',
    'Cannot Print Page',
    'User Intervention Required',
    'Out of Memory',
    'Server Unknown',
);

sub isEnabled {
    my (%params) = @_;

    return !$params{no_category}->{printer};
}

sub doInventory {
    my (%params) = @_;

    my $inventory = $params{inventory};
    my $logger    = $params{logger};

    foreach my $object (getWMIObjects(
        class      => 'Win32_Printer',
        properties => [ qw/
            ExtendedDetectedErrorState HorizontalResolution VerticalResolution Name
            Comment DescriptionDriverName DriverName PortName Network Shared 
            PrinterStatus ServerName ShareName PrintProcessor
        / ]
    )) {

        my $errStatus;
        if ($object->{ExtendedDetectedErrorState}) {
            $errStatus = $errStatus[$object->{ExtendedDetectedErrorState}];
        }

        my $resolution;

        if ($object->{HorizontalResolution}) {
            $resolution =
                $object->{HorizontalResolution} .
                "x"                             .
                $object->{VerticalResolution};
        }

        $object->{Serial} = _getUSBPrinterSerial($object->{PortName}, $logger)
            if $object->{PortName} && $object->{PortName} =~ /USB/;

        $inventory->addEntry(
            section => 'PRINTERS',
            entry   => {
                NAME           => $object->{Name},
                COMMENT        => $object->{Comment},
                DESCRIPTION    => $object->{Description},
                DRIVER         => $object->{DriverName},
                PORT           => $object->{PortName},
                RESOLUTION     => $resolution,
                NETWORK        => $object->{Network},
                SHARED         => $object->{Shared},
                STATUS         => $status[$object->{PrinterStatus}],
                ERRSTATUS      => $errStatus,
                SERVERNAME     => $object->{ServerName},
                SHARENAME      => $object->{ShareName},
                PRINTPROCESSOR => $object->{PrintProcessor},
                SERIAL         => $object->{Serial}
            }
        );

    }    
}

sub _getUSBPrinterSerial {
    my ($portName, $logger) = @_;

    # find the ParentIdPrefix value for the printer matching given portname
    my $prefix = _getUSBPrefix(
        getRegistryKey(
            path => "HKEY_LOCAL_MACHINE/SYSTEM/CurrentControlSet/Enum/USBPRINT",
            logger => $logger
        ),
        $portName
    );
    return unless $prefix;

    # find the key name for the device matching given parentIdPrefix
    my $serial = _getUSBSerial(
        getRegistryKey(
            path => "HKEY_LOCAL_MACHINE/SYSTEM/CurrentControlSet/Enum/USB",
            logger => $logger
        ),
        $prefix
    );

    return $serial;
}

sub _getUSBPrefix {
    my ($print, $portName) = @_;

    # registry data structure:
    # USBPRINT
    # └── device
    #     └── subdevice
    #         └── Device Parameters
    #             └── PortName:value

    foreach my $device (values %$print) {
        foreach my $subdeviceName (keys %$device) {
            my $subdevice = $device->{$subdeviceName};
            next unless 
                $subdevice->{'Device Parameters/'}                &&
                $subdevice->{'Device Parameters/'}->{'/PortName'} &&
                $subdevice->{'Device Parameters/'}->{'/PortName'} eq $portName;
            # got it
            my $prefix = $subdeviceName;
            $prefix =~ s{&$portName/$}{};
            return $prefix;
        };
    }

    return;
}

sub _getUSBSerial {
    my ($usb, $prefix) = @_;

    # registry data structure:
    # USB
    # └── device
    #     └── subdevice
    #         └── ParentIdPrefix:value

    foreach my $device (values %$usb) {
        foreach my $subdeviceName (keys %$device) {
            my $subdevice = $device->{$subdeviceName};
            next unless
                $subdevice->{'/ParentIdPrefix'} &&
                $subdevice->{'/ParentIdPrefix'} eq $prefix;
            # got it
            my $serial = $subdeviceName;
            # pseudo serial generated by windows
            return if $serial =~ /&/;
            $serial =~ s{/$}{};
            return $serial;
        }
    }

    return;
}

1;
