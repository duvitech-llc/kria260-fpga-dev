# Vendor firmware (not in git)

The AP1302 image signal processor on the KV260's IAS0 camera path (J7) has no
flash of its own: the A53 loads its firmware over I2C every time (`cam=isp`,
`sw/board_test/cam_isp.c`).

The firmware is AMD's, published in the Ubuntu source package
`linux-firmware-xilinx-ap1302` (version 2.0). It is not ours to redistribute,
so this folder only holds the script that fetches it:

```bash
python -I sw/firmware/get_ap1302_fw.py
```

It downloads the package tarball here, extracts `ap1302_ar1335_single_fw.bin`
(79324 bytes, CRC 0xA152 in its header) and writes
`sw/board_test/ap1302_fw.h`. Rebuild the board test afterwards
(`vitis -s create_vitis.py app`). Without the header the ISP capture test
reports SKIP.
