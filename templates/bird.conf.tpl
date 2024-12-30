router id ${ router_id };

protocol device {
  scan time 10;  # Scan interfaces every 10 seconds
}

protocol kernel {
  ipv4 {
    import all;
    export all;
  };
  learn;  # Learn routes from the kernel
}

protocol ospf v2 {
  ipv4 {
    import all;
    export all;
  };
  area 0 {
   interface "gre1" {
      hello 10;  # Hello interval in seconds
      dead 40;
      cost 10;   # Interface cost
   };
  };
}

