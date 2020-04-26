import requests
import json

'''
author:wanglibao
date created:2020/03/11
Introduction:根据标签名称创建监控。
'''


zabbix_url = "https://node_zabbix.xunyou.mobi/api_jsonrpc.php"
ipURL = "https://ops.xunyou.mobi/api/v1/ip?limit=9999"
tagsURL = "https://ops.xunyou.mobi/api/v1/tags"
zabbix_username = "admin"
zabbix_password = "zabbix"
Content_type = "application/json"
Authorization = "Token 12a537cb1786bf26b530ebae2ca3daa355492dd1"
zabbix_headers={'Content-Type': 'application/json-rpc'}
zabbix_data = {"jsonrpc": "2.0",
          'method': "user.login",
          "params": {
              "user": zabbix_username,
              "password": zabbix_password,
          },
          "id": 0,
          }
headers = {
    "Content-Type": Content_type,
    "Authorization": Authorization
}

keyname = ["traffic_out", "traffic_in"]
#cmdb中创建的标签名称，赋值到tag_name，程序根据tag_name创建主机组，根据tag_name查询tag里面的主机信息。并创建监控。
tag_name = "南京腾讯云"
#将需关联的模板赋值到templates，列表中包含模板名称即可。
templates = ['Converge Node Log Template','New Subao Node Services','process_log','REST Monitor','Subao Node OS']
def getZabbixAuth():
    response = requests.post(url=zabbix_url,data=json.dumps(zabbix_data),headers=zabbix_headers)
    auth = json.loads(response.text)['result']
    return auth
auth = getZabbixAuth()



def getDataList(url,headers):
    data = requests.get(url=url,headers=headers)
    results = data.json()
    return results


def getHosts(hostname):
    data = {
        "jsonrpc": "2.0",
        "method": "host.get",
        "params": {
            "output": "extend",
            "filter": {
                "name": [
                    hostname
                ]
            }
        },
        "auth": auth,
        "id": 1
    }
    response = requests.post(url=zabbix_url, data=json.dumps(data), headers=zabbix_headers)
    results = response.json()['result']
    return results

def getHostGroup(groupName=None,AllGroups=False):
    groupData = {
        "jsonrpc": "2.0",
        "method": "hostgroup.get",
        "params": {
            "output": "extend",
            "filter": {
                "name": [
                    groupName,
                ]
            }
        },
        "auth": auth,
        "id": 1
    }
    allGroupsData = {
        "jsonrpc": "2.0",
        "method": "hostgroup.get",
        "params": {
            "output": "extend",
        },
        "auth": auth,
        "id": 1
    }
    if AllGroups:
        response = requests.get(url=zabbix_url, data=json.dumps(allGroupsData), headers=zabbix_headers)
    else:
        response = requests.get(url=zabbix_url, data=json.dumps(groupData), headers=zabbix_headers)
    results = response.json()['result']
    return results

def getTemplates(templatenames=None,groupid=None,group=False):
    data = {
        "jsonrpc": "2.0",
        "method": "template.get",
        "params": {
            "output": "extend",
            "filter": {
                "host": templatenames
            }
        },
        "auth": auth,
        "id": 1
    }
    data_g = {
        "jsonrpc": "2.0",
        "method": "hostgroup.get",
        "params": {
            "output": 'extend',
            "filter": {
                "groupid": groupid
            },
            "selectTemplates": [
                "host",
                "templateid"
            ],
        },
        "auth": auth,
        "id": 1
    }
    if group:
        response = requests.get(url=zabbix_url, data=json.dumps(data_g), headers=zabbix_headers)
        results = response.json()
        print(results)
        teplateid_list = []
        for result in results['result']:
            for template in result['templates']:
                teplateid_list.append(template['templateid'])

        return teplateid_list
    else:
        response = requests.get(url=zabbix_url, data=json.dumps(data), headers=zabbix_headers)
        results = response.json()
        return results
def getItemId(hostid,keyname):
    data = {
        "jsonrpc": "2.0",
        "method": "item.get",
        "params": {
            "output": "extend",
            "hostids": hostid,
            "search": {
                "key_": keyname
            },
            "sortfield": "name"
        },
        "auth": auth,
        "id": 1
    }
    response = requests.post(url=zabbix_url, data=json.dumps(data), headers=zabbix_headers)
    result = response.json()['result']
    if len(result) >= 1:
        for i in result:
            # print("获取itemID:{0}".format(i.get("itemid")))
            itemid = i.get("itemid")
        return itemid
    else:
        return False

def updateItem(itemid,params):
    data = {
        "jsonrpc": "2.0",
        "method": "item.update",
        "params": {
            "itemid": itemid,
            "status": 0,
            "params": params,
        },
        "auth": auth,
        "id": 1
    }
    response = requests.post(url=zabbix_url, data=json.dumps(data), headers=zabbix_headers)
    result = response.json()['result']

def createHost(hostname,ipaddr,groupid):
    json_base = {
        "jsonrpc": "2.0",
        "method": "host.create",
        "params": {
            "host": hostname,
            "name": hostname,
            "interfaces": [
                {
                    "type": 1,
                    "main": 1,
                    "useip": 1,
                    "ip": ipaddr,
                    "dns": "",
                    "port": "10050"
                }
            ],
            "groups": [
                {
                    "groupid": groupid
                }
            ],
            "inventory_mode": 0
        },
        "auth": auth,
        "id": 1
    }
    response = requests.post(url=zabbix_url, data=json.dumps(json_base), headers=zabbix_headers)
    result = response.json()
    if 'result' in result.keys():
        print('success')
        content = 'zabbix创建主机:{}'.format(hostname)
    else :
        print(result['error']['data'])
        content = 'zabbix创建主机:{}'.format(hostname)

def creatGroup(groupname):
    data = {
        "jsonrpc": "2.0",
        "method": "hostgroup.create",
        "params": {
            "name": groupname
        },
        "auth": auth,
        "id": 1
    }
    response = requests.post(url=zabbix_url, data=json.dumps(data), headers=zabbix_headers)
    results = response.json()

def template_massadd_host(templateid_list,hostid):
    templates = []
    hosts = []
    for templateid in templateid_list:
        template = {
            "templateid": templateid
        }
        templates.append(template)
    data = {
        "jsonrpc": "2.0",
        "method": "template.massadd",
        "params": {
            "templates": templates,
            "hosts": [
                {
                    "hostid":hostid
                }
            ]
        },
        "auth": auth,
        "id": 1
    }
    response = requests.get(url=zabbix_url, data=json.dumps(data), headers=zabbix_headers)
    results = response.json()
    return results

def main():
    ips = getDataList(ipURL, headers)
    ips = ips['results']
    tags = getDataList(tagsURL, headers)
    tags = tags['results']
    hostlist = []
    templateid_list = []
    for template_name in templates:
        results = getTemplates(templatenames=template_name)
        templateid = results['result'][0]['templateid']
        templateid_list.append(templateid)
    for tag in tags:
        if tag['tags'] == tag_name:
            group_info = getHostGroup(groupName=tag_name, AllGroups=False)
            if group_info:
                print("{groupname},主机组存在".format(groupname=tag_name))
            else:
                print("{groupname},主机组不存在".format(groupname=tag_name))
                creatGroup(tag_name)
            servers = tag['servers']
            for server in servers:
                server = getDataList(server, headers)
                hostname = server['hostname']
                network_card = []
                for ip in ips:
                    if server['url'] == ip['server']:
                        if 'local' != ip['ip_type']:
                            iface_name = ip['iface_name']
                            network_card.append(iface_name)
                        if 'public' == ip['ip_type']:
                            if 'ctc' in ip['isp']:
                                ipaddr = ip['ipaddr']
                            elif 'cmcc' == ip['isp']:
                                ipaddr = ip['ipaddr']
                            elif 'cnc' == ip['isp']:
                                ipaddr = ip['ipaddr']
                        elif 'nat' == ip['ip_type']:
                            ipaddr = ip['ipaddr']
                    else:
                        continue
                if network_card:
                    results = getHosts(hostname)
                    if results:
                        hostlist.append(results[0]['hostid'])
                    else:
                        groupsinfo = getHostGroup(tag_name, AllGroups=False)
                        groupid = groupsinfo[0]['groupid']
                        # print(group_info)
                        createHost(hostname, ipaddr, groupid)
                        # print(ipaddr)
                        results = getHosts(hostname)
                        if results:
                            print("{hostname}主机创建成功。。。".format(hostname=hostname))
                            # hostlist.append(results[0]['hostid'])
                            hostid = results[0]['hostid']
                            template_massadd_host(templateid_list, hostid)
                            for key in keyname:
                                params = ''
                                if key == "traffic_in":
                                    type = "in"
                                elif key == "traffic_out":
                                    type = "out"
                                for j in range(len(network_card)):
                                    param = "last(\"net.if." + type + "[" + network_card[j] + "]\",0)"
                                    params = param + "+" + params
                                params = params[:-1]
                                itemid = getItemId(hostid, key)
                                if itemid:
                                    updateItem(itemid, params)
                                else:
                                    continue
                                    print("{}主机不存在key:{}".format(hostname, key))
                        else:
                            print("创建主机{hostname}失败".format(hostname=hostname))

main()
