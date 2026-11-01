/* Slideshow shown while Linux Light installs (Calamares slideshow API 2). */
import QtQuick 2.0;
import calamares.slideshow 1.0;

Presentation
{
    id: presentation

    Timer {
        interval: 12000
        running: presentation.activatedInCalamares
        repeat: true
        onTriggered: presentation.goToNextSlide()
    }

    function onActivate() { }
    function onLeave() { }

    Slide {
        Image {
            id: logo1
            source: "logo.png"
            width: 128; height: 128
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: 40
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: logo1.bottom
            anchors.topMargin: 24
            width: 600
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
            font.pixelSize: 18
            text: qsTr("Installing Linux Light.<br/>" +
                       "The rest runs by itself and takes a few minutes.")
        }
    }

    Slide {
        Text {
            anchors.centerIn: parent
            width: 600
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
            font.pixelSize: 18
            text: qsTr("After the restart, log in with the user name and password " +
                       "you chose.<br/><br/>Super+F1 shows all keyboard shortcuts " +
                       "(Super is the Windows key).")
        }
    }

    Slide {
        Text {
            anchors.centerIn: parent
            width: 600
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
            font.pixelSize: 18
            text: qsTr("Wi-Fi: network icon at the top right, or Super+n.<br/>" +
                       "Screens (mirror / extend): Super+Shift+p.<br/>" +
                       "Touchpad settings: Super+Shift+t.")
        }
    }

    Slide {
        Text {
            anchors.centerIn: parent
            width: 600
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
            font.pixelSize: 18
            text: qsTr("More software: sudo apt update, then sudo apt install " +
                       "followed by the package name.<br/><br/>Updates, including " +
                       "new kernels, come with sudo apt upgrade.")
        }
    }
}
