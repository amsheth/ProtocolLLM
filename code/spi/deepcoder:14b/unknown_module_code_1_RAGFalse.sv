def spi_send_data(data):
    # Assuming CPOL is 0 (clock idle low), CS is already pulled low
    for i in range(7, -1, -1):
        # Set the MOSI pin based on the current bit
        if (data >> i) & 1:
            mosi_pin = 1
        else:
            mosi_pin = 0
        
        # Toggle the SCK pin to send the clock pulse
        sck_pin = 1
        delay()  # Ensure enough time for the slave to capture data
        sck_pin = 0
    
    # After sending all bits, ensure SCK is in idle state (if CPOL is 0)
    if cpol == 0:
        sck_pin = 0