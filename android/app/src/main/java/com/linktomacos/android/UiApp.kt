package com.linktomacos.android

import android.app.Application
import com.linktomacos.android.ipc.ServiceClient

/** 界面 App：本身不连 Mac、不存配对，一切经 [ServiceClient] 交给服务 App。 */
class UiApp : Application() {
    val client by lazy { ServiceClient(this) }
}
