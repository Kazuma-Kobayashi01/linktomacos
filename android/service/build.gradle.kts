plugins {
    alias(libs.plugins.android.application)
}

// 后台服务 App：没有桌面图标，负责连接 Mac、转发通知、剪贴板、AirSend、增强服务。
android {
    namespace = "com.linktomacos.android.service"
    compileSdk = 37

    defaultConfig {
        applicationId = "com.linktomacos.android.service"
        minSdk = 35
        targetSdk = 35
        versionCode = 110
        versionName = "1.1.0"
    }

    buildTypes {
        release {
            // 开启压缩和优化。增强服务（shell 包）由 app_process 按类名启动、还靠反射调用系统内部接口，规则见 proguard-rules.pro
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            signingConfig = signingConfigs.getByName("debug")
            ndk { abiFilters += "arm64-v8a" }
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

dependencies {
    implementation(project(":core"))
}
