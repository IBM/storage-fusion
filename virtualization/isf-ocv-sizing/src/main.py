from gui import MainWindow
import sys
from PyQt5.QtWidgets import QApplication

def main():
    """
    Entry point for the application.
    """
    app = QApplication(sys.argv)
    window = MainWindow()
    window.show()
    sys.exit(app.exec_())

if __name__ == '__main__':
    main()

