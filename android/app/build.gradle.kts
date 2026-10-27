plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
}

android {
    namespace = "com.linktomacos.android.app"
    compileSdk = 37

    defaultConfig {
        applicationId = "com.linktomacos.android"
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
            // 仅自用：用调试密钥签名，这样 release 包能直接安装
            signingConfig = signingConfigs.getByName("debug")
            // 手机是 arm64-v8a，只打这一种架构，包更小
            ndk { abiFilters += "arm64-v8a" }
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    buildFeatures {
        compose = true
    }
}

dependencies {
    implementation(project(":core"))
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(platform(libs.compose.bom))
    implementation(libs.compose.ui)
    implementation(libs.compose.material3)
    implementation(libs.compose.ui.tooling.preview)
    debugImplementation(libs.compose.ui.tooling)
    implementation(libs.camerax.camera2)
    implementation(libs.camerax.lifecycle)
    implementation(libs.camerax.view)
    implementation(libs.zxing.core)
}
