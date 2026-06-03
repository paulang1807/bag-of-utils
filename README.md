# <img src="docs/app-icon.png" width="48" align="center" alt="Bag of Utils Icon"> Bag of Utils

**Bag of Utils** is a modular, high-performance macOS utility application suite. Engineered to be ultra-lightweight and visually stunning, it brings native-grade desktop tools directly to your Mac.

The suite starts with a robust, visual **File Renamer** utility, designed to handle bulk file renaming tasks safely and efficiently.

---

## 📸 Media Demonstration

### Application Interface Mockup
![Bag of Utils User Interface](docs/ui-screenshot.png)

---

## 🌟 Key Features (File Renamer)

* **Multiple Naming Patterns**: Choose between sequential numbering (`Prefix_001.ext`, `Prefix-001.ext`, `Prefix 001.ext`) or prepending/reformatting (`Prefix_OriginalName.ext`).
* **Real-time Live Preview**: View exactly what the files will be renamed to *before* applying any changes.
* **Collision & Conflict Detection**: Identifies and flags name clashes (duplicate target names) before execution, keeping your data safe.
* **Vibrant macOS Integration**: Features native macOS vibrancy (frosted glass glassmorphism), borderless titlebar styling, native traffic-light buttons overlay, and direct Finder integration.
* **Stateless & Safe**: Operates directly on the directories you specify using native Cocoa filesystem APIs.

---

## 🛠 Tech Stack

* **Native Wrapper & Shell**: Swift (AppKit & WebKit frameworks)
* **User Interface**: HTML5, Vanilla CSS3 (Glassmorphic theme), ES6 JavaScript
* **IPC communication**: Asynchronous Promise-based WebKit Script Bridge
* **Unit Testing**: Node.js Native Test Runner (`node --test`)
* **Assets compilation**: macOS `sips` (Scriptable Image Processing System) and `iconutil`

---

## 🚀 Prerequisites & Local Setup

### System Requirements
* macOS 10.15 (Catalina) or later.
* macOS Xcode Command Line Tools or full Xcode package (provides the `swiftc` compiler).
* Node.js v18.0.0 or later (for running unit tests).

### Quick Compilation & Setup

1. **Clone the Repository**:
   ```bash
   git clone https://github.com/paulang1807/bag-of-utils.git
   cd bag-of-utils
   ```

2. **Build the App Bundle**:
   Run the automated build script to compile the Swift source, package the resources, and output a double-clickable Mac app bundle under the `build/` directory:
   ```bash
   npm run build
   ```

3. **Run the App**:
   You can launch the compiled app immediately from your terminal or double-click `BagOfUtils.app` inside the `build/` directory in Finder:
   ```bash
   open build/BagOfUtils.app
   ```

---

## 🧪 Running Unit Tests

Validate the core renaming, indexing, padding, and conflict detection logic using the native Node.js test runner:
```bash
npm test
```

---

## 📖 Usage Guide

1. **Open a Target Folder**: Launch **Bag of Utils** and click **Browse...** to select the directory containing the files you wish to rename.
2. **Configure Naming Rules**:
   * Enter your desired **Name Prefix** (e.g. `Vacation`).
   * Select a **Naming Format** from the dropdown menu.
   * Adjust **Start Index** and **Digits Padding** values (options dynamically display based on format).
3. **Inspect the Preview**: View the files table in the live preview panel. Verify the destination names:
   * **Cyan highlights** indicate modified filenames.
   * **Faded rows** indicate unchanged filenames.
   * **Red highlights and warning icons** indicate name collisions.
4. **Execute**: When you are satisfied with the preview (and no conflicts exist), click **Rename Files**. The files will be renamed in-place and the preview list will refresh automatically.
5. **Quick Reveal**: Click **Show in Finder** at any point to open the folder and verify the changes on disk.

---

## 📂 Project Structure

```
bag-of-utils/
├── build.sh            # Packages Resources & compiles App binary
├── package.json        # Project metadata, ES Modules setup, npm scripts
├── Info.plist          # macOS App Bundle property list configuration
├── docs/               # Documentation images & media assets
│   ├── app-icon.png
│   └── ui-screenshot.png
├── src/
│   ├── swift/
│   │   └── main.swift  # Native window controls & script IPC bridge
│   └── web/            # HTML/CSS/JS frontend
│       ├── index.html
│       ├── style.css
│       ├── renamer.js  # Main renaming logic module
│       └── renderer.js # UI event controllers
└── test/
    └── renamer.test.js # Native Node.js tests suite
```
