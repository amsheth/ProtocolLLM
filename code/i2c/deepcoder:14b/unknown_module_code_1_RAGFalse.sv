def i2c_master():
    global state, cnt, data_ptr, address

    while True:
        if state == IDLE:
            # Wait for start command
            if start_command_received():
                send_start_condition()
                state = ADDRESSING
                data_ptr = 0
                break
        
        elif state == ADDRESSING:
            # Send address byte and wait for ACK
            send_byte(address >> (7 - cnt))
            if cnt == 8:
                state = WAIT_ACK
                cnt = 0
            else:
                cnt += 1
        
        elif state == WAIT_ACK:
            # Wait for ACK after address
            if sda.read() == LOW:
                state = DATA_TRANSMISSION
                data_ptr = 0
                send_data()
            else:
                # Handle NACK, possibly repeat or stop
                pass
        
        # ... other states for data transmission and stopping

    return