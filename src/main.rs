extern crate rustless;
extern crate hyper;
extern crate iron;
extern crate valico;
extern crate crypto;

#[macro_use(bson, doc)]
extern crate bson;
extern crate mongodb;

use mongodb::{Client, ThreadedClient};
use mongodb::db::ThreadedDatabase;
use bson::
{
    Bson,
    Document
};

use std::fs;
use std::fs::File;
use std::io::BufReader;
use std::io::Read;
use std::path::Path;
use std::process::Command;
use std::thread;
use std::time::
{
    SystemTime,
    UNIX_EPOCH
};
use crypto::digest::Digest;
use crypto::sha3::Sha3;
use valico::json_dsl;
use rustless::server::status::StatusCode;
use rustless::json::ToJson;
use rustless::
{
    Application,
    Api,
    Nesting,
    Versioning
};
use hyper::header::
{
    ContentDisposition,
    DispositionType,
    DispositionParam,
    Charset
};

const GBS_DIR:&str = "/var/lib/gbs";

fn check(path:&str) -> Option<&str>
{
    let p = Path::new(path).file_name()?.to_str()?;
    if p == path
    {
        return Some(path);
    }
    else
    {
        return None;
    }
}

fn is_atom(repository:&str, category:&str, package:&str, version:&str) -> Option<()>
{

    let r = check(repository)?;
    let c = check(category)?;
    let p = check(package)?;
    let v = check(version)?;

    if Path::new(&format!("{}/repos/{}/{}/{}/{}-{}.ebuild", GBS_DIR, r, c, p, p, v)).is_file()
    {
        return Some(());
    }
    else
    {
        return None;
    }
}

fn is_build_request(repository:&str, category:&str, package:&str, version:&str, id:&str) -> Option<()>
{

    let r = check(repository)?;
    let c = check(category)?;
    let p = check(package)?;
    let v = check(version)?;
    let i = check(id)?;

    if Path::new(&format!("{}/packages/{}/{}/{}/{}/{}", GBS_DIR, r, c, p, v, i)).is_dir()
    {
        return Some(());
    }
    else
    {
        return None;
    }
}

fn build_id(repository:&str, category:&str, package:&str, version:&str, uses:&[(String, bool)]) -> String
{
    let mut hasher = Sha3::sha3_256();
    hasher.input_str(&format!("{}{}{}{}", repository, category, package, version));

    for &(ref key, ref value) in uses.iter()
    {
        hasher.input_str(&format!("{}{} ", match *value {true => "", false => "-"}, key));
    }
    return hasher.result_str();
}

#[test]
fn test_is_atom()
{
    assert_eq!(false, is_atom("test","test","test","test").is_some());
    assert_eq!(false, is_atom("test/.","test/../.","test","test").is_some());
    assert_eq!(false, is_atom("gentoo/.","app-editors","vim","8.0.1298").is_some());
    assert_eq!(false, is_atom("gentoo","app-editors","vim","8").is_some());
    assert_eq!(true, is_atom("gentoo","app-editors","vim","8.0.1298").is_some());
}

fn main()
{
    let client = Client::connect("localhost", 27017)
        .expect("Failed to initialize standalone client.");
    let coll = client.db("gbs").collection("builds");

    let api = Api::build(|api|
    {
        api.prefix("api");
        api.version("1", Versioning::Path);

        api.namespace("atoms/:repositories/:categories/:packages/:versions", |atoms_ns|
        {
            atoms_ns.params(|params|
            {
                params.req_typed("repositories", json_dsl::string());
                params.req_typed("categories", json_dsl::string());
                params.req_typed("packages", json_dsl::string());
                params.req_typed("versions", json_dsl::string());
            });
            atoms_ns.get("builds", |endpoint|
            {
                endpoint.handle(|client, params|
                {
                    return client.json(&params.to_json());
                })
            });
            atoms_ns.get("builds/:id/status", |endpoint|
            {
                endpoint.params(|params|
                {
                    params.req_typed("id", json_dsl::string());
                });
                endpoint.handle(|mut client, params|
                {
                    let repository = params.find("repositories").unwrap().to_string().trim_matches('"').to_string();
                    let category = params.find("categories").unwrap().to_string().trim_matches('"').to_string();
                    let package = params.find("packages").unwrap().to_string().trim_matches('"').to_string();
                    let version = params.find("versions").unwrap().to_string().trim_matches('"').to_string();
                    let id = params.find("id").unwrap().to_string().trim_matches('"').to_string();

                    if is_build_request(&repository, &category, &package, &version, &id).is_some()
                    {
                        let s = format!("{}/packages/{}/{}/{}/{}/{}/status", GBS_DIR, repository, category, package, version, id);
                        let path = Path::new(&s);
                        if path.is_file()
                        {
                            let f = File::open(&s).unwrap();
                            let mut reader = BufReader::new(f);
                            let mut buf = String::new();
                            reader.read_to_string(&mut buf);
                            return client.text(buf);
                        }
                    }
                    client.set_status(StatusCode::NotFound);
                    return client.empty();
                })
            });
            atoms_ns.get("builds/:id/log", |endpoint|
            {
                endpoint.params(|params|
                {
                    params.req_typed("id", json_dsl::string());
                });
                endpoint.handle(|mut client, params|
                {
                    let repository = params.find("repositories").unwrap().to_string().trim_matches('"').to_string();
                    let category = params.find("categories").unwrap().to_string().trim_matches('"').to_string();
                    let package = params.find("packages").unwrap().to_string().trim_matches('"').to_string();
                    let version = params.find("versions").unwrap().to_string().trim_matches('"').to_string();
                    let id = params.find("id").unwrap().to_string().trim_matches('"').to_string();

                    if is_build_request(&repository, &category, &package, &version, &id).is_some()
                    {
                        let s = format!("{}/packages/{}/{}/{}/{}/{}/log", GBS_DIR, repository, category, package, version, id);
                        let path = Path::new(&s);
                        if path.is_file()
                        {
                            let f = File::open(&s).unwrap();
                            let mut reader = BufReader::new(f);
                            let mut buf = String::new();
                            reader.read_to_string(&mut buf);
                            return client.text(buf);
                        }
                    }
                    client.set_status(StatusCode::NotFound);
                    return client.empty();
                })
            });
            atoms_ns.get("builds/:id", |endpoint|
            {
                endpoint.params(|params|
                {
                    params.req_typed("id", json_dsl::string());
                });
                endpoint.handle(|mut client, params|
                {
                    let repository = params.find("repositories").unwrap().to_string().trim_matches('"').to_string();
                    let category = params.find("categories").unwrap().to_string().trim_matches('"').to_string();
                    let package = params.find("packages").unwrap().to_string().trim_matches('"').to_string();
                    let version = params.find("versions").unwrap().to_string().trim_matches('"').to_string();
                    let id = params.find("id").unwrap().to_string().trim_matches('"').to_string();

                    if is_build_request(&repository, &category, &package, &version, &id).is_some()
                    {
                        let s = format!("{}/packages/{}/{}/{}/{}/{}/{3}-{4}.tbz2", GBS_DIR, repository, category, package, version, id);
                        let path = Path::new(&s);
                        if path.is_file()
                        {
                            client.set_header(ContentDisposition
                            {
                              disposition: DispositionType::Attachment,
                              parameters: vec![DispositionParam::Filename(
                                Charset::Us_Ascii,
                                None,
                                format!("{}-{}.tbz2", package, version).into_bytes()
                            )]});
                            return client.file(path);
                        }
                    }
                    client.set_status(StatusCode::NotFound);
                    return client.empty();
                })
            });
            atoms_ns.post("builds", |endpoint|
            {
                endpoint.handle(move |mut client, params|
                {
                    let repository = params.find("repositories").unwrap().to_string().trim_matches('"').to_string();
                    let category = params.find("categories").unwrap().to_string().trim_matches('"').to_string();
                    let package = params.find("packages").unwrap().to_string().trim_matches('"').to_string();
                    let version = params.find("versions").unwrap().to_string().trim_matches('"').to_string();

                    let mut uses = String::new();
                    let use_flag = params.find("use").unwrap();
                    for (key, value) in use_flag.as_object().unwrap().iter()
                    {
                        uses.push_str(&format!("{}{} ", match value.as_bool().unwrap(){true => "", false => "-"}, key));
                    }
                    let mut uu :Vec<(String, bool)> = Vec::new();
                    for (key, value) in use_flag.as_object().unwrap().iter()
                    {
                        uu.push((key.clone(), value.as_bool().unwrap()));
                    }
                    let id = build_id(&repository, &category, &package, &version, &uu);
                    println!("{}/{}/{}/{}", repository, category, package, version);
                    println!("USE=\"{}\"", uses);

                    let url = format!("{}/{}/{}/{}/builds/{}", repository, category, package, version, id);

                    if is_atom(&repository, &category, &package, &version).is_some()
                    {
                        if !is_build_request(&repository, &category, &package, &version, &id).is_some()
                        {
                            {
                                let mut uses = Document::new();
                                for (key, value) in use_flag.as_object().unwrap().iter()
                                {
                                    uses.insert(key.clone(), Bson::Boolean(value.as_bool().unwrap().clone()));
                                }
                                let s = SystemTime::now();
                                let doc = doc!
                                {
                                    "date" => &format!("{}", s.duration_since(UNIX_EPOCH).unwrap().as_secs()),
                                    "id" => id.clone(),
                                    "repository" => repository.clone(),
                                    "category" => category.clone(),
                                    "package" => package.clone(),
                                    "version" => version.clone(),
                                    "use" => uses
                                };
                                coll.insert_one(doc.clone(), None).ok().expect("Failed to insert document.");
                            }
                            thread::spawn(move ||
                            {
                                fs::create_dir_all(format!("{}/packages/{}/{}/{}/{}/{}", GBS_DIR, repository, category, package, version, id)).unwrap();
                                let b = Command::new("docker")
                                .arg("run")
                                .arg("--rm")
                                .arg("-v")
                                .arg(format!("{}/distfiles:/usr/portage/distfiles", GBS_DIR))
                                .arg("-v")
                                .arg(format!("{}/repos:/var/db/repos:ro", GBS_DIR))
                                .arg("-v")
                                .arg(format!("{}/ccache:/mnt/ccache", GBS_DIR))
                                .arg("-v")
                                .arg(format!("{}/packages/{}/{}/{}/{}/{}:/mnt/package", GBS_DIR, repository, category, package, version, id))
                                .arg("--cap-add=SYS_PTRACE")
                                .arg("-idt")
                                .arg("--name")
                                .arg(format!("{}_{}_{}_{}_{}", repository, category, package, version, id))
                                .arg("gentoo:gbs")
                                .arg("/usr/bin/build_script.sh")
                                .arg(repository)
                                .arg(category)
                                .arg(package)
                                .arg(version)
                                .arg(uses)
                                .output().unwrap();
                                println!("{}\n", String::from_utf8_lossy(&b.stdout));
                                println!("{}\n", String::from_utf8_lossy(&b.stderr));
                            });
                        }
                        return client.text(url);
                    }
                    else
                    {
                        client.set_status(StatusCode::NotFound);
                        return client.empty();
                    }
                })
            });
        });
    });

    let app = Application::new(api);

    iron::Iron::new(app).http("0.0.0.0:4000").unwrap();
}
