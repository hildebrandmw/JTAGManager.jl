using Test
using JTAGManager

using Sockets


# Create a little server to connect to.
@async begin
    storage = zeros(UInt8, 10)
    server = listen(2540)
    while true

        socket = accept(server)
        @async while isopen(socket)
            message = readline(socket)

            # Check if writing. Store written data to "storage"
            if startswith(message, "jtag_write")
                # Get the start address and the data.
                split_message = split(message, " ")

                # Add 1 to start address to correct for base 0 addressing.
                start_address = parse(Int, split_message[2]) + 1
                payload = parse.(UInt8, split_message[3:end])

                # Construct writing range.
                write_range = start_address:(start_address + length(payload) - 1)
                storage[write_range] .= payload

            # Check if a read is being performed. Return the requested
            # data.
            elseif startswith(message, "jtag_read")
                split_message = split(message, " ")

                # Add 1 to start address to correct for base 0 addressing.
                start_address = parse(Int, split_message[2]) + 1
                num_bytes = parse(Int, split_message[3])

                read_range = start_address:(start_address + num_bytes - 1)
                return_message = join(storage[read_range], " ")

                println(socket, return_message)
            end
        end
    end
end

@testset "Testing Writer" begin
    # Wait for a little bit for the above task to get scheduled.
    sleep(1)

    # Open up default JTAG.
    jtag = JTAG()
    @test jtag.isopen == false

    # Test 1
    write(jtag, 0, [1,2,3])
    @test jtag.isopen == true
    sleep(0.5)
    data = read(jtag, 0, 3)
    @test data == [1,2,3]

    # Test 2
    write(jtag, 2, [1,2,3,4,5])
    sleep(0.5)
    data = read(jtag, 0, 5)
    @test data == [1,2,1,2,3]

    close(jtag)
    @test jtag.isopen == false
end
