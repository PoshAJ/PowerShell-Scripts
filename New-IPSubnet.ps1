<#PSScriptInfo

    .VERSION 1.0.3

    .GUID 3bb10ee7-38c1-41b9-88ea-16899164fc19

    .AUTHOR Anthony J. Raymond

    .COMPANYNAME

    .COPYRIGHT (c) 2022 Anthony J. Raymond

    .TAGS ip subnet network ipv4 ipv6

    .LICENSEURI https://github.com/CodeAJGit/posh/blob/master/LICENSE

    .PROJECTURI https://github.com/CodeAJGit/posh

    .ICONURI

    .EXTERNALMODULEDEPENDENCIES

    .REQUIREDSCRIPTS

    .EXTERNALSCRIPTDEPENDENCIES

    .RELEASENOTES
        20220302-AJR: v1.0.0 - Initial Release
        20220302-AJR: v1.0.1 - Fix Clerical Errors and Added Tags
        20220305-AJR: v1.0.2 - Updated Metadata
        20220305-AJR: v1.0.3 - Replace void cast with $null

    .PRIVATEDATA

#>

<#

    .DESCRIPTION
        Creates an [IPSubnet] object for use to manipulate IPv4 & IPv6 subnets.

    .EXAMPLE
        .\New-IPSubnet.ps1 192.168.1.0/30

    .EXAMPLE
        .\New-IPSubnet.ps1 -Subnet 2001:db8::1 -Prefix 32

    .PARAMETER Subnet
        Specifies an IPv4 or IPv6 address.

    .PARAMETER Prefix
        <Optional> Specifies the prefix (or network portion) of the address.

#>
[CmdletBinding()]
[OutputType([object])]

## PARAMETERS #############################################################
param (
    [Parameter(
        Mandatory,
        Position = 0
    )]
    [string]
    $Subnet,

    [Parameter()]
    [ValidateRange(0, 128)]
    [int]
    $Prefix = ($Subnet -isplit "\\|\/")[-1]
)

## BEGIN ##################################################################
begin {
    Write-Verbose "start begin block"
    class IPSubnet : System.Object {
        # class properties ################################################
        [System.Net.IPAddress] $Network
        [System.Net.Sockets.AddressFamily] $AddressFamily
        [ValidateRange(0, 128)] [int] $Prefix
        [System.Net.IPAddress] $SubnetMask
        [System.Net.IPAddress] $LastAddress

        [bigint] hidden $PrefixInt
        [bigint] hidden $StartInt
        [bigint] hidden $EndInt

        # class methods ###################################################
        [string] ToString() {
            return ("{0}/{1}" -f $this.Network, $this.Prefix)
        }

        [bool] Contains([System.Net.IPAddress] $InputIPAddress) {
            # compute and compare network address
            $InputAddress = $this.ToAddress($InputIPAddress, $false) -band $this.PrefixInt
            $NetworkAddress = $this.ToAddress($this.Network, $false)

            return ($NetworkAddress -eq $InputAddress)
        }

        [IPSubnet[]] Subnet([int] $InputPrefix) {
            $Power = switch ($this.AddressFamily) {
                "InterNetwork" { [bigint]::Pow(2, (32 - $InputPrefix)) }
                "InterNetworkV6" { [bigint]::Pow(2, (128 - $InputPrefix)) }
            }
            $Subnets = for ($AddressInt = $this.StartInt; $AddressInt -le $this.EndInt; $AddressInt += $Power) {
                [IPSubnet]::new(($this.FromAddress($AddressInt, $true)), $InputPrefix)
            }
            return $Subnets
        }

        [bigint] hidden ToAddress([System.Net.IPAddress] $InputIPAddress, [bool] $Reverse) {
            # here we go address -> bytes -> reverse -> bigint
            [byte[]] $Bytes = $InputIPAddress.GetAddressBytes()

            if ($Reverse) {
                [array]::Reverse($Bytes)
            }
            # append zero byte for unsigned
            return [bigint]::new($Bytes + 0)
        }

        [System.Net.IPAddress] hidden FromAddress([bigint] $InputInt, [bool] $Reverse) {
            # here we go backward bigint -> bytes -> reverse -> address
            [byte[]] $Bytes = $InputInt.ToByteArray()

            # we're going to pad the array for the size that the IPAddress constructor expects
            switch ($this.AddressFamily) {
                "InterNetwork" { [array]::Resize([ref] $Bytes, 4) }
                "InterNetworkV6" { [array]::Resize([ref] $Bytes, 16) }
            }
            if ($Reverse) {
                [array]::Reverse($Bytes)
            }
            return [System.Net.IPAddress] $Bytes
        }

        [bigint] hidden GetPrefixInt([int] $InputInt) {
            # turn prefix into binary string so we can work with it
            $Binary = switch ($this.AddressFamily) {
                "InterNetwork" { ('1' * $InputInt).PadRight(32, '0') }
                "InterNetworkV6" { ('1' * $InputInt).PadRight(128, '0') }
            }
            # the last element of this match is null, so skip it
            $Octet = $Binary -isplit "(?<=\G[01]{8})" | Select-Object -SkipLast 1
            $Bytes = $Octet | ForEach-Object { [System.Convert]::ToUInt32($_, 2) }

            # append zero byte for unsigned
            return [bigint]::new($Bytes + 0)
        }

        [void] hidden __init__([System.Net.IPAddress] $InputIPAddress, [int] $InputPrefix) {
            $this.Prefix = $InputPrefix
            $this.AddressFamily = $InputIPAddress.AddressFamily

            # quick prefix validation
            switch ($true) {
                { $this.AddressFamily -eq "InterNetwork" -and $this.Prefix -iin 0..32 } { break }
                { $this.AddressFamily -eq "InterNetworkV6" -and $this.Prefix -iin 0..128 } { break }
                default { throw [System.InvalidCastException] "An invalid prefix for the given address family was specified." }
            }
            $this.PrefixInt = $this.GetPrefixInt($this.Prefix)
            $this.SubnetMask = $this.FromAddress($this.PrefixInt, $false)

            # using the prefix we can find the network address
            $StartAddress = $this.ToAddress($InputIPAddress, $false) -band $this.PrefixInt
            $this.Network = $this.FromAddress($StartAddress, $false)

            # using the prefix, we can find the last address
            $EndAddress = switch ($this.AddressFamily) {
                "InterNetwork" { $StartAddress -bor (-bnot $this.PrefixInt -band ([bigint]::Pow(2, 32) - 1)) }
                "InterNetworkV6" { $StartAddress -bor (-bnot $this.PrefixInt -band ([bigint]::Pow(2, 128) - 1)) }
            }
            $this.LastAddress = $this.FromAddress($EndAddress, $false)

            $this.StartInt = $this.ToAddress($this.Network, $true)
            $this.EndInt = $this.ToAddress($this.LastAddress, $true)

            Update-TypeData -TypeName IPSubnet -MemberType AliasProperty -MemberName Broadcast -Value LastAddress -Force
            Update-TypeData -TypeName IPSubnet -MemberType AliasProperty -MemberName Mask -Value SubnetMask -Force
            Update-TypeData -TypeName IPSubnet -DefaultDisplayPropertySet Network, AddressFamily, Prefix, LastAddress -Force
        }

        # class constructors ##############################################
        IPSubnet([System.Net.IPAddress] $InputIPAddress, [int] $InputPrefix) {
            $this.__init__($InputIPAddress, $InputPrefix)
        }

        IPSubnet([string] $InputString) {
            try {
                $SplitString = $InputString -isplit "\\|\/"
                [System.Net.IPAddress] $InputIPAddress = $SplitString[0]
                [int] $InputPrefix = $SplitString[-1]
            } catch {
                throw [System.InvalidCastException] "An invalid IP address or prefix format was specified."
            }
            $this.__init__($InputIPAddress, $InputPrefix)
        }
    }
}

## PROCESS ################################################################
process {
    Write-Verbose "start process block"
    [IPSubnet]::new(($Subnet -isplit "\\|\/")[0], $Prefix)
}

## END ####################################################################
end {
    Write-Verbose "start end block"
    $null = [System.GC]::GetTotalMemory($true)
}
