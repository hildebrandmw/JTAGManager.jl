module JTAGManager

export JTAG

# external dependencies
using ProgressMeter

# stdlib dependencies
using Sockets 

# Messages - for interfacing the the TCL server running in either Quartus 
# SystemConsole or STP.
jtag_open(id = 0) = "jtag_open $id"
jtag_close() = "jtag_close"
jtag_write(start, data) = "jtag_write $start $(join(data, " "))"
jtag_read(start, bytes) = "jtag_read $start $bytes"


"""
    JTAG(ip = ip"127.0.0.1", port = 2540) :: JTAG

Stand-in type for controlling communication to a TCL server running in Quartus
SystemConsole. Provides remote access to the JTAG read and write mechanisms.

API: `open`, `close`, `write`, `read`
"""
mutable struct JTAG{T <: IPAddr}
    ip :: T
    port :: Int
    # Remember if the JTAG Connection has been opened yet.
    # Default to false on construction.
    isopen :: Bool
end

JTAG(ip::IPAddr = ip"127.0.0.1", port::Int = 2540) = JTAG(ip, port, false)

Sockets.connect(jtag::JTAG) = connect(jtag.ip, jtag.port)

"""
    open(jtag::JTAG)

Open the SystemConsole connection to an FPGA. Should not be commonly called
directly.
"""
function Base.open(jtag::JTAG)
    socket = connect(jtag)
    println(socket, jtag_open())
    close(socket)
    # Set open flag.
    jtag.isopen = true
    return nothing
end
safeopen(jtag::JTAG) = (jtag.isopen || open(jtag); return nothing)

"""
    close(jtag::JTAG)

Close the SystemConsole connection to an FPGA.
"""
function Base.close(jtag::JTAG)
    socket = connect(jtag) 
    println(socket, jtag_close())
    close(socket)
    # Clear open flag.
    jtag.isopen = false
end

"""
    write(jtag::JTAG, address, data; bytes_per_transfer = 2^18)

Write `data` to the connected device starting at `addresses`. If `data` is a 
large vector, break it up into sizes of `bytes_per_transfer`.
"""
Base.write(jtag::JTAG, address, data::Integer; kwargs...) = write(jtag, address, [data]; kwargs...)
function Base.write(
            jtag::JTAG, 
            address,
            data;
            bytes_per_transfer = 2 ^ 18,
       )

    # Establish connection if it hasn't been established yet.
    safeopen(jtag)

    # Open the socket to the TCL server
    socket = connect(jtag)

    # Compute the number of transfers
    ntransfers = ceil(Int, length(data) / bytes_per_transfer)

    # Transfer data in chunks
    @showprogress for i in 1:ntransfers
        # Compute start address for this transfer
        start = address + bytes_per_transfer * (i-1)

        # Get the index range of data for this transfer
        idx_low = bytes_per_transfer * (i-1) + 1
        idx_high = min(bytes_per_transfer * i, length(data))

        transfer_data = view(data, idx_low:idx_high)

        # Send the data over TCP
        println(socket, jtag_write(start, transfer_data))
    end
    close(socket)
end


"""
    read(jtag::JTAG, address, bytes; bytes_per_transfer = 2^18) :: Vector{UInt8}

Read `bytes` number of bytes from the JTAG device starting at `address`.
"""
function Base.read(jtag::JTAG, address, bytes; bytes_per_transfer = 2^18)

    # Do the standard setup
    safeopen(jtag)
    socket = connect(jtag)
    ntransfers = ceil(Int, length(bytes) / bytes_per_transfer)

    # Data to store result.
    data = UInt8[]
    sizehint!(data, bytes)

    @showprogress for i in 1:ntransfers
        start = address + bytes_per_transfer * (i-1)

        println(socket, jtag_read(start, bytes))
        back_string = readline(socket)

        # Split the returned string on spaces, parse back as UInt8
        split_string = split(back_string, " ")
        append!(data, parse.(UInt8, split_string))
    end

    close(socket)

    return data
end

end # module
