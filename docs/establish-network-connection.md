***

## Part 1: Establish Network Connection 🌐

This section covers the complete process of getting your server online, from the initial physical wiring to configuring the operating system.

### 1.1 Physical Connection

First, you must physically connect your **Inspur i24** server. The rear panel has two types of network ports for this purpose.



* **OCP/PHY Ports**: These are the primary network interfaces for the server's operating system and general network traffic.
* **IPMI Port**: This is a dedicated port for the Baseboard Management Controller (**BMC**) that enables remote management. The **IPMI port alone is not sufficient** for the server's primary internet connection.

#### Cable Requirements
* **Cable Type**: Use a standard **Ethernet patch cable** with **RJ-45** connectors.
* **Recommendation**: For optimal performance (1 Gbps and higher), a **Category 6 (Cat6)** or **Category 6a (Cat6a)** cable is highly recommended.

#### Connection Steps
1.  Locate the **OCP** or **PHY** network ports on the back of the server.
2.  Using your Ethernet cable, connect one of these ports to an available port on your **network switch**.
3.  Ensure the switch is connected to your primary router to provide internet access.

---

### 1.2 Accessing the Server Console 🖥️

Once the server is wired and powered on, you need to access its console.

* **Remote Access (BMC):** The recommended method, using the dedicated IPMI port for remote control.
* **Direct Physical Access (SUV Port):** Involves connecting a monitor, keyboard, and mouse directly.

#### Remote Access via BMC (Recommended)
1.  **Find the BMC IP Address:** Locate the IP address assigned to the server's BMC port, typically by checking the client list on your network router.
2.  **Log In:** On another computer on the same network, open a web browser and go to the BMC IP address. Use the default credentials:
    * **Username:** `admin`
    * **Password:** `admin`
3.  **Launch the Remote Console:** Inside the Inspur management system, navigate to **Console Redirection** and click **Launch KVM HTML5 Viewer**. This opens a virtual display of the server's UI.



---

### 1.3 Configure and Verify OS Network ⚙️

With console access, the final step is to configure the operating system to use the network.

*Note: If this is the first boot of a new OS, you may need to create a user profile before proceeding.*

#### Configuration and Verification Steps
1.  In the server's OS, navigate to **Settings** > **Network**.
2.  Identify the interface corresponding to the connected OCP/PHY port (e.g., **ens35f0**).
3.  **Enable** the Ethernet connection. The status should update to **Connected**, showing the link speed (e.g., `10000 Mb/s`).
4.  Open a **Terminal** and verify connectivity by running `ping 8.8.8.8`. You should see successful replies.

***


